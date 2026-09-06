# 🎵 Audio Clip & Combine

**A privacy-first, browser-based audio editor** for trimming, speed-adjusting, and stitching
audio clips together — plus a couple of small command-line helpers for downloading source audio
and doing the same edits from the terminal.

**Live app:** https://d2ju4uav1sxpa.cloudfront.net/

Everything runs client-side. No file is ever uploaded anywhere — decoding, trimming, speed
changes, waveform rendering, and MP3/WAV encoding all happen locally in your browser using the
Web Audio API and an in-browser MP3 encoder.

---

## What it does

Add one or more local audio files, and for each one:

- **Trim** it to a `[start, end]` range (typed as `MM:SS`, or drag the markers directly on the
  waveform).
- **Change its speed** (0.5×–3×) with **pitch preserved** — no chipmunk or demon effects.
- **Preview** it in place: play/pause/restart, loop the clip, and see a live waveform with a
  moving playhead.
- **Reorder, duplicate, or remove** tracks, then **play them all back-to-back** in order.
- **Export**: download the whole sequence as one combined file, or each clip individually — as
  MP3 or lossless WAV, with an optional short cross-fade between joins.

Your settings (clip ranges, speeds, loop state, track order) are saved to `localStorage` and
restored the next time you open the page — the audio files themselves can't be persisted by a
browser, so you're prompted to re-pick them.

### Small quality-of-life details
- Dark/light theme toggle (persisted).
- Full keyboard shortcuts: <kbd>Space</kbd> play/pause, <kbd>←</kbd>/<kbd>→</kbd> seek (hold
  <kbd>Shift</kbd> for a bigger step), <kbd>[</kbd>/<kbd>]</kbd> set start/end to the current
  playhead position.
- Drag-and-drop audio files directly onto a track card.
- Screen-reader support: live-region announcements for key actions, labelled controls, and a
  descriptive `aria-label` on the waveform canvas.
- Graceful handling of files the browser can't decode (clear inline message instead of a silent
  failure).

## Try it

Open **https://d2ju4uav1sxpa.cloudfront.net/** — no install, no account, no upload.

## Run it locally

It's a single static HTML file with no build step and no dependencies beyond the bundled
encoder:

```bash
git clone https://github.com/balaji4aws/audio-tools.git
cd audio-tools
python3 -m http.server 8000     # or any static file server
```

Then open http://localhost:8000.

---

## Command-line helpers

The web app covers interactive editing. Two shell scripts cover the surrounding workflow —
pulling in source audio and doing the same clip/speed/combine edits without a browser, e.g. for
batch or scripted use.

### `download.sh` — pull audio from YouTube

Downloads the best-available audio track (as `.m4a`) from a YouTube video or playlist into
`downloads/`. Requires [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) (`brew install yt-dlp`) and a
Chrome profile you're logged into (used only to read cookies locally, for age-gated/throttled
videos — nothing is sent anywhere beyond the normal YouTube request).

```bash
./download.sh "https://youtu.be/VIDEO_ID"     # single video
./download.sh "PLAYLIST_URL"                  # whole playlist
./download.sh URL1 URL2 URL3                  # multiple videos
```

Sleep/retry intervals are preconfigured to avoid rate-limit blocks, and a download archive
(`downloads/.download-archive.txt`) skips files you've already grabbed.

### `audio_edit.sh` — cut, speed-adjust, and combine via ffmpeg

The command-line equivalent of the web app's core edit-and-combine flow, for when you'd rather
script it than click through a UI. Requires [`ffmpeg`](https://ffmpeg.org/).

```bash
./audio_edit.sh <in> <start> <end> <speed> [<in> <start> <end> <speed> ...] <output>
```

Each input file gets its own `[start, end]` cut and its own speed factor (pitch preserved, via
ffmpeg's `atempo` — arbitrarily large/small factors are decomposed into a valid filter chain);
all resulting segments are concatenated in order into one output file.

```bash
# Speed up the first 45s of song A by 1.5x, slow down a 20s clip from song B by 0.75x, combine:
./audio_edit.sh songA.mp3 0:00 0:45 1.5 songB.mp3 1:00 1:20 0.75 combined.mp3

# Whole file, 2x speed, no trimming:
./audio_edit.sh song.wav 0 end 2.0 fast.mp3
```

Run `./audio_edit.sh --help` for the full argument reference. Times accept `SS`, `MM:SS`, or
`HH:MM:SS`; `end` means "to the end of the file."

### `deploy.sh` — redeploy this app to AWS

Uploads `index.html` and `lame.min.js` to the S3 bucket backing the live app and invalidates the
CloudFront cache, using bucket/distribution details from a local `.deploy-info` file (not
committed — this is personal deployment config, not part of the app itself).

```bash
./deploy.sh
```

You don't need this unless you're deploying your own copy to your own AWS account.

---

## How it's built

Everything client-side lives in a single `index.html` — no framework, no bundler, no build step.

- **Web Audio API** (`AudioContext.decodeAudioData`) decodes each uploaded file and computes a
  small peaks array for the waveform, drawn on a `<canvas>` that redraws on resize, theme change,
  and every animation frame while a clip plays.
- **Speed changes preserve pitch** two different ways depending on context:
  - **Live preview** uses `<audio>`'s native `preservesPitch` (with the vendor-prefixed
    fallbacks browsers still need).
  - **Export** uses a hand-written windowed **overlap-add (OLA) time-stretch** directly on the
    decoded PCM data, so the exported file matches what you heard in preview.
- **Export encoding**: WAV is a straightforward 16-bit PCM encode; MP3 uses the bundled
  [`lamejs`](https://github.com/zhuker/lamejs) encoder (a JavaScript port of the LAME encoder),
  chunked with `await`ed yields so the progress bar stays responsive during encoding.
- **Session persistence**: clip ranges, speeds, loop flags, and track order are saved to
  `localStorage` (`cc-session`) — not the audio files themselves, which browsers can't persist.

```
audio-tools/
├── index.html        # the entire web app: markup, styles, and logic
├── lame.min.js        # bundled MP3 encoder (lamejs — LGPL, see Credits)
├── audio_edit.sh      # CLI: cut + speed-adjust + combine via ffmpeg
├── download.sh        # CLI: download audio from YouTube via yt-dlp
├── deploy.sh          # deploy index.html/lame.min.js to S3 + invalidate CloudFront
└── downloads/         # yt-dlp output (gitignored — your own local downloads)
```

## Privacy

Nothing you load into the app ever leaves your browser. There's no backend, no upload endpoint,
and no analytics. The only network activity the app itself makes is loading the page's own static
files. (`download.sh` is a separate, local CLI tool that does talk to YouTube — that's the point
of it — but it isn't part of the web app.)

## Browser support

Requires the Web Audio API and `<audio>` — works in current Chrome, Edge, Firefox, and Safari.
Speed changes rely on `HTMLMediaElement.preservesPitch` (and vendor-prefixed equivalents), which
all major browsers support. If a file can't be decoded by the browser's audio decoder, the app
tells you clearly instead of failing silently — try re-exporting it as MP3 or WAV first.

## Credits

- [lamejs](https://github.com/zhuker/lamejs) — in-browser MP3 encoder (JavaScript port of
  [LAME](https://lame.sourceforge.io/)), bundled as `lame.min.js`, licensed LGPL.
- [ffmpeg](https://ffmpeg.org/) — powers `audio_edit.sh`.
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) — powers `download.sh`.

## Author

Built by **Balaji Venkatesh** — [LinkedIn](https://www.linkedin.com/in/venkyb27) — with
[Kiro](https://kiro.dev).

## License

No license file is currently included, which under default copyright law means all rights to the
original code are reserved by the author. (`lame.min.js` retains its own LGPL license from the
upstream project regardless.) Add an [OSI-approved license](https://choosealicense.com/) here if
you'd like to allow reuse.
