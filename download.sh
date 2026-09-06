#!/usr/bin/env bash
# Download best-quality audio (m4a) from YouTube into audio-tools/downloads/.
# Cookies, throttling, and resume are preconfigured to avoid bot/429 blocks.
#
# Usage:
#   ./download.sh "https://youtu.be/VIDEO_ID"          # single video
#   ./download.sh "PLAYLIST_URL"                        # whole playlist
#   ./download.sh URL1 URL2 URL3                        # multiple
set -euo pipefail
cd "$(dirname "$0")"

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <youtube-url> [more-urls...]" >&2
  exit 1
fi

command -v yt-dlp >/dev/null 2>&1 || {
  echo "Error: yt-dlp is not installed or not on PATH. Install it with 'brew install yt-dlp' (macOS) or see https://github.com/yt-dlp/yt-dlp#installation." >&2
  exit 1
}

# Browser to pull YouTube login cookies from. We use Chrome.
BROWSER="${BROWSER:-chrome}"

DEST="downloads"
mkdir -p "$DEST"

yt-dlp \
  --cookies-from-browser "$BROWSER" \
  -x --audio-format m4a --audio-quality 0 \
  --sleep-requests 2 --min-sleep-interval 5 --max-sleep-interval 15 \
  --retries 3 --file-access-retries 3 \
  --download-archive "$DEST/.download-archive.txt" \
  -o "$DEST/%(playlist_index|)s%(playlist_index& - |)s%(title)s.%(ext)s" \
  "$@"

echo "Done. Files saved in $(pwd)/$DEST/"
