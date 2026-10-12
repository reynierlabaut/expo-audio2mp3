# Changelog

## Unreleased

- iOS: AVAssetReader decoder with system PCM conversion, C bridge to `Audio2Mp3Core.xcframework`, background task (pending device testing).

## 0.1.0 — 2026-10-12

First release, **Android only**.

### 🎉 New features

- `convertToMp3` (V1): extracts the audio of a video or audio file and saves it as CBR MP3 (64–320 kbps).
- Android: MediaExtractor + MediaCodec decoder, PCM conversion with `PcmConverter` (audio2mp3-core, feature `pcm-convert`), JNI bridge with direct `ByteBuffer`s.
- Info frame (Xing + LAME) for exact duration and gapless playback.
- Writes to `<output>.part` and renames at the end; never leaves partial files.
- `startConversion` (V1.1): returns a `ConversionJob` with `promise`, `cancel()` (rejects with `CANCELLED`) and `addProgressListener` (0.0 → 1.0, throttled).
- Web stub that rejects with `UNSUPPORTED_PLATFORM`.
- `scripts/fetch-core.sh` (pinned version + sha256), `scripts/check-alignment.sh` (16 KB), fixtures and ffprobe validation scripts.
