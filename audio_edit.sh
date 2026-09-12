#!/usr/bin/env bash
#
# audio_edit.sh — cut, speed-adjust, and append multiple audio files with ffmpeg.
#
# Each input file is cut to a [start, end] range and given its OWN speed factor,
# then all the resulting segments are appended (concatenated) in order into one
# output file.
#
# Usage:
#   ./audio_edit.sh <in> <start> <end> <speed> [<in> <start> <end> <speed> ...] <output>
#
# Arguments (in repeating groups of 4, one group per input file):
#   <in>     path to an input audio file
#   <start>  start of the cut. Formats: SS | MM:SS | HH:MM:SS  (e.g. 90, 1:30, 0:01:30)
#   <end>    end of the cut, same formats. Use "end" to keep until the file's end.
#   <speed>  playback speed multiplier (pitch preserved). e.g. 1.0 = no change,
#            1.5 = 50% faster, 0.75 = 25% slower. Any positive value is allowed.
#   <output> final combined file (last argument). Extension sets the format (.mp3, .m4a, .wav...)
#
# Examples:
#   ./audio_edit.sh in1.mp3 0:10 0:45 1.5 in2.mp3 1:00 1:20 0.75 final.mp3
#   ./audio_edit.sh song.wav 0 end 2.0 fast.mp3          # whole file, 2x speed
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

# Print the leading comment header (the usage block) and exit. Stops at the
# first non-comment line so the body of the script is never echoed.
usage() {
  awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
  exit "${1:-0}"
}

# Convert SS | MM:SS | HH:MM:SS -> seconds (float). Prints the number, or the
# literal "NaN" if the input isn't a well-formed time. Every colon-separated
# field must be a plain (optionally fractional) number — awk would otherwise
# coerce junk like "abc" to 0 and silently accept it.
to_seconds() {
  awk -v t="$1" 'BEGIN {
    n = split(t, p, ":")
    if (t == "" || n < 1 || n > 3) { print "NaN"; exit }
    for (i = 1; i <= n; i++)
      if (p[i] !~ /^[0-9]+(\.[0-9]+)?$/) { print "NaN"; exit }
    if (n == 1)      s = p[1]
    else if (n == 2) s = p[1]*60 + p[2]
    else             s = p[1]*3600 + p[2]*60 + p[3]
    printf "%.6f", s
  }'
}

# Build an atempo filter chain for an arbitrary positive speed factor.
# ffmpeg's atempo accepts 0.5..2.0 per instance, so we decompose larger/
# smaller factors into a chain (e.g. 3.0 -> atempo=2.0,atempo=1.5).
#
# The shape check comes FIRST and is deliberately strict: a non-numeric value
# compares as a string against the loop bounds, which used to send the halving
# loop into an unbounded spin (it never converges because "abc"/2 is 0, and
# 0 < 0.5 forever), hanging the script and eating memory.
build_atempo() {
  awk -v s="$1" 'BEGIN {
    if (s !~ /^[0-9]+(\.[0-9]+)?$/ || s + 0 <= 0) { print "BAD"; exit }
    s = s + 0
    out = ""
    # factor down toward 1.0 using 2.0 steps while too fast
    while (s > 2.0 + 1e-9) { out = out "atempo=2.0,"; s /= 2.0 }
    # factor up toward 1.0 using 0.5 steps while too slow
    while (s < 0.5 - 1e-9) { out = out "atempo=0.5,"; s /= 0.5 }
    out = out sprintf("atempo=%.6f", s)
    print out
  }'
}

# ---------------------------------------------------------------------------
# Argument parsing / validation
# ---------------------------------------------------------------------------

[ $# -eq 0 ] && usage 0
{ [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; } && usage 0

command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg is not installed or not on PATH."

# Need at least one group of 4 + 1 output = 5 args, and (argc - 1) divisible by 4.
[ $# -ge 5 ] || die "Not enough arguments. Run with --help for usage."
if [ $(( ($# - 1) % 4 )) -ne 0 ]; then
  die "Each input needs exactly 4 values (file start end speed), plus one output at the end."
fi

# Last argument is the output; everything before is input groups.
OUTPUT="${!#}"
NUM_GROUPS=$(( ($# - 1) / 4 ))

# Temp workspace for intermediate segments (cleaned up on exit).
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/audio_edit.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

CONCAT_LIST="$WORKDIR/segments.txt"
: > "$CONCAT_LIST"

# Common intermediate format so appending is always reliable regardless of the
# input codecs/sample rates. We normalize each segment to 44.1kHz stereo WAV,
# concatenate losslessly, then encode once to the requested output format.
SR=44100
CH=2

echo "Processing $NUM_GROUPS file(s)..."

for (( g=0; g<NUM_GROUPS; g++ )); do
  base=$(( g*4 + 1 ))
  file="${!base}"
  start="${@:$((base+1)):1}"
  end="${@:$((base+2)):1}"
  speed="${@:$((base+3)):1}"

  [ -f "$file" ] || die "Input file not found: $file"

  start_s="$(to_seconds "$start")"
  [ "$start_s" = "NaN" ] && die "Bad start time '$start' for '$file' (use SS, MM:SS, or HH:MM:SS)."

  atempo="$(build_atempo "$speed")"
  [ "$atempo" = "BAD" ] && die "Bad speed '$speed' for '$file' (must be a positive decimal number, e.g. 1.0, 1.5, 0.75)."

  seg="$WORKDIR/seg_$(printf '%03d' "$g").wav"

  # Trim on the INPUT side (both -ss and -t before -i) so we read the raw cut
  # FIRST, then apply the speed filter. If -t were an output option it would
  # truncate AFTER atempo and clip slowed-down segments.
  input_args=(-ss "$start_s")
  if [ "$end" != "end" ]; then
    end_s="$(to_seconds "$end")"
    [ "$end_s" = "NaN" ] && die "Bad end time '$end' for '$file' (use SS, MM:SS, HH:MM:SS, or 'end')."
    dur="$(awk -v a="$start_s" -v b="$end_s" 'BEGIN{ printf "%.6f", b - a }')"
    awk -v d="$dur" 'BEGIN{ exit !(d > 0) }' || die "End must be after start for '$file' ($start -> $end)."
    input_args+=(-t "$dur")
  fi

  printf '  [%d/%d] %s  cut %s -> %s  speed x%s\n' \
    "$((g+1))" "$NUM_GROUPS" "$file" "$start" "$end" "$speed"

  ffmpeg -hide_banner -loglevel error -y \
    "${input_args[@]}" -i "$file" \
    -filter:a "$atempo" \
    -ar "$SR" -ac "$CH" -c:a pcm_s16le \
    "$seg"

  # concat demuxer needs single-quoted, escaped paths
  printf "file '%s'\n" "${seg//\'/\'\\\'\'}" >> "$CONCAT_LIST"
done

echo "Combining segments -> $OUTPUT"
ffmpeg -hide_banner -loglevel error -y \
  -f concat -safe 0 -i "$CONCAT_LIST" \
  "$OUTPUT"

echo "Done: $OUTPUT"
