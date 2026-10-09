# Changelog

## Unreleased

### 🎉 New features

- `convertToMp3` (V1): extracts the audio of a video or audio file and saves it as CBR MP3 (64–320 kbps).
- Android: MediaExtractor + MediaCodec decoder, PCM conversion with `PcmConverter` (audio2mp3-core, feature `pcm-convert`), JNI bridge with direct `ByteBuffer`s.
- iOS: AVAssetReader decoder with system PCM conversion, C bridge to `Audio2Mp3Core.xcframework`, background task.
- Info frame (Xing + LAME) for exact duration and gapless playback.
- Writes to `<output>.part` and renames at the end; never leaves partial files.
- Internal job id, cancellation registry and throttled progress, ready for the V1.1 public API.
- Web stub that rejects with `UNSUPPORTED_PLATFORM`.
- `scripts/fetch-core.sh` (pinned version + sha256), `scripts/check-alignment.sh` (16 KB), fixtures and ffprobe validation scripts.
