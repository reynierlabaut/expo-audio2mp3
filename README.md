# 🎧 expo-audio2mp3 - Expo MP3 Converter

**English** | [Español](README.es.md)

An Expo native module that extracts the audio of a video or audio file and saves it as MP3. Decoding is done by the operating system (MediaExtractor + MediaCodec on Android, AVAssetReader on iOS) and encoding by [audio2mp3-core](https://github.com/reynierlabaut/audio2mp3-core), a small MP3 encoder written in Rust that ships precompiled.

```text
video / audio ─► OS decoder ─► PCM ─► audio2mp3-core ─► MP3
```

It is only an integration layer: no FFmpeg, no bundled decoders, no C/C++ for you to compile and no Rust toolchain needed.

## ✨ Features
- 🎬 **Any container the OS can open:** MP4, MOV, M4A, 3GP, WebM, MKV, MP3, WAV, OGG, FLAC, AAC...
- 🎚️ **CBR 64–320 kbps** with an Info frame (Xing + LAME) for exact duration and gapless playback.
- 🔊 **Automatic format handling:** 5.1 → stereo downmix and resampling to 32 / 44.1 / 48 kHz.
- 🧵 **Off the main and JS threads:** conversions run one at a time on a dedicated serial queue.
- 🧹 **Never leaves a half-written MP3:** it writes to `<output>.part` and renames at the end.
- 🪶 **Small:** target ≤ 300 KB per ABI on Android and ≤ 300 KB on iOS.

## 📋 Requirements
- Expo SDK 54+ with the **New Architecture**.
- A **development build** (`npx expo prebuild` / EAS Build). **Expo Go is not supported.**
- Android minSdk 24+. Web is not supported (rejects with `UNSUPPORTED_PLATFORM`).

> ⚠️ **0.1.x is Android only.** The iOS implementation is in the repository but has not been tested on a device yet; it will ship in a later release.

## 📦 Installation

```bash
npx expo install expo-audio2mp3
npx expo prebuild   # or an EAS Build
```

No config plugin is needed.

## 🚀 Usage

```ts
import { File, Paths } from 'expo-file-system';
import { convertToMp3, Audio2Mp3Error } from 'expo-audio2mp3';

try {
  const result = await convertToMp3({
    input: videoUri, // e.g. the uri returned by expo-document-picker
    output: new File(Paths.document, 'song.mp3').uri,
    bitrate: 192, // optional, default 192
    overwrite: false, // optional, default false
  });
  console.log(result.uri, result.durationMs);
} catch (error) {
  if (error instanceof Audio2Mp3Error && error.code === 'NO_AUDIO_TRACK') {
    // the video has no audio
  }
}
```

To save the MP3 to the music library, use `expo-media-library` (or similar) with `result.uri`.

## 📖 API

### `convertToMp3(options): Promise<ConvertResult>`

| Option | Type | Default | Description |
|---|---|---|---|
| `input` | `string` | — | `file://`, `content://` (Android) or absolute path. Video or audio. |
| `output` | `string` | — | `file://` or absolute path inside the app sandbox. |
| `bitrate` | `64 \| 96 \| 128 \| 160 \| 192 \| 224 \| 256 \| 320` | `192` | CBR bitrate in kbps. |
| `overwrite` | `boolean` | `false` | If `false` and `output` exists, rejects with `OUTPUT_EXISTS`. |

`ConvertResult`: `uri` (`file://` of the MP3), `durationMs`, `sizeBytes`, `sampleRate` (32000 \| 44100 \| 48000), `channels` (1 \| 2), `bitrate`.

### `startConversion(options): ConversionJob`

Same options, with progress and cancellation. `convertToMp3(o)` is `startConversion(o).promise`.

```ts
const job = startConversion({ input, output, bitrate: 192 });
const sub = job.addProgressListener(p => setProgress(p)); // 0.0 → 1.0, at most every 100 ms / 1 %
job.cancel(); // the promise rejects with CANCELLED and no partial file is left
const result = await job.promise;
sub.remove();
```

No progress is emitted if the input does not report its duration.

### Errors

Every rejection is an `Audio2Mp3Error` with a `code`:

| Code | When |
|---|---|
| `FILE_NOT_FOUND` | The input does not exist. |
| `PERMISSION_DENIED` | The input cannot be read (missing permission or security scope). |
| `INVALID_PATH` | Empty, relative or malformed path; `output` is a directory or `content://`; input and output are the same file. |
| `NO_AUDIO_TRACK` | The file has no audio track. |
| `UNSUPPORTED_FORMAT` | The OS cannot open or decode the file on this device. |
| `DRM_PROTECTED` | The file is DRM protected. |
| `DECODER_ERROR` | The OS decoder failed mid-way. |
| `ENCODER_ERROR` | audio2mp3-core failed. |
| `INVALID_BITRATE` | `bitrate` is not one of the allowed values. |
| `OUTPUT_EXISTS` | `output` exists and `overwrite` is `false`. |
| `OUTPUT_ERROR` | The output folder does not exist or is not writable, or writing failed. |
| `INSUFFICIENT_SPACE` | Not enough free space (estimated as `duration × bitrate / 8 × 1.1`). |
| `CANCELLED` | The conversion was cancelled (e.g. iOS expired its background time). |
| `UNSUPPORTED_PLATFORM` | Called on web. |

### ⚠️ Supported formats depend on the device

The module uses the decoders of the operating system, so **the real list of formats depends on the device and OS version** (for example, WebM/Opus always works on Android but depends on the iOS version). Always handle `UNSUPPORTED_FORMAT`.

## 📏 Size and performance

Measured on physical devices (a mid-range Android, an iPhone at least 3 years old), comparing the app before and after adding the module:

| Metric | Target | Measured |
|---|---|---|
| APK increase per ABI (arm64-v8a) | ≤ 300 KB | `libaudio2mp3.so` = 299 KB (uncompressed); app pending |
| IPA increase | ≤ 300 KB | pending |
| 10 min video → MP3 on mid-range Android | ≤ 60 s | pending |
| Extra memory during a conversion | ≤ 10 MB, constant | pending |

## 🛠️ Development

```bash
npm install
npm run fetch-core              # downloads audio2mp3-core (version pinned in core-version.json)
npm test                        # jest-expo: ios, android, web and node
npm run build                   # TypeScript → build/
bash scripts/check-alignment.sh # 16 KB alignment of the .so files (needs the NDK)
```

- `scripts/fetch-core.sh --from ../audio2mp3-core/dist` installs the binaries from a local core build.
- Updating the core = change the version and checksums in `core-version.json`, run the script and publish a new version of the module.
- The `example/` app is a development build: `cd example && npm install && npx expo run:android`.
- Native tests: `cd example/android && ./gradlew :expo-audio2mp3:connectedAndroidTest` (Android) and the `Tests` test spec of the podspec (iOS).
- Integration fixtures: `scripts/make-fixtures.sh` creates the fixture matrix with ffmpeg (a dev tool, not shipped) and `scripts/check-mp3.sh` validates each MP3 with ffprobe.

```text
src/              TypeScript API (convertToMp3, types, validation, web stub)
android/          Kotlin: Expo module, MediaExtractor/MediaCodec decoder, JNI bridge
ios/              Swift: Expo module, AVAssetReader decoder, C bridge, XCTest
scripts/          fetch-core, check-alignment, fixtures and ffprobe validation
example/          Expo test app (development build)
```

## 📄 License

MIT

<div align="center">
<pre style="user-select: none; -webkit-user-select: none; -moz-user-select: none; -ms-user-select: none; display: inline-block; text-align: left; font-family: monospace; font-size: 12px; line-height: 1.2; background: transparent; border: none; box-shadow: none;">
███████╗███╗   ██╗ █████╗ ██╗  ██╗███████╗        ███████╗██╗   ██╗███████╗███████╗
██╔════╝████╗  ██║██╔══██╗██║ ██╔╝██╔════╝        ██╔════╝╚██╗ ██╔╝██╔════╝██╔════╝
███████╗██╔██╗ ██║███████║█████╔╝ █████╗          █████╗   ╚████╔╝ █████╗  ███████╗
╚════██║██║╚██╗██║██╔══██║██╔═██╗ ██╔══╝          ██╔══╝    ╚██╔╝  ██╔══╝  ╚════██║
███████║██║ ╚████║██║  ██║██║  ██╗███████╗███████╗███████╗   ██║   ███████╗███████║
╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝   ╚══════╝╚══════╝
</pre>
  <div style="text-align: center; font-family: sans-serif;">
  <strong><em>Code clean, Strike fast</em></strong><br>
  <span style="margin-top: 5px;">@RyLabaut</span>
  </div>
</div>
