# expo-audio2mp3 — contexto para agentes

Módulo nativo de Expo (Expo Modules API, Kotlin + Swift) que extrae el audio de un vídeo/audio y lo convierte a MP3.
Spec completa: `docs/SPEC.md` (v2). **Cualquier función que no esté en la spec se discute antes de implementarla.**

```text
vídeo / audio ─► decoder del sistema ─► PCM ─► audio2mp3-core ─► MP3
```

## Reglas

- Sin FFmpeg/GStreamer/LibAV/Symphonia, sin decoders propios, sin otro encoder, sin C/C++ que compile el consumidor.
- El encoder es `audio2mp3-core` (Rust, repo aparte) **precompilado**; versión y sha256 en `core-version.json`.
  Los binarios no van a git: `npm run fetch-core` (o `scripts/fetch-core.sh --from ../audio2mp3-core/dist`).
- Solo New Architecture; Expo Go y web no soportados (web rechaza con `UNSUPPORTED_PLATFORM`).
- Los códigos de error son los mismos en `src/types.ts`, `android/.../Errors.kt` e `ios/Errors.swift`.

## Estructura

- `src/`: `index.ts` (`convertToMp3`), `job.ts` (jobId, cancelación y progreso internos, V1.1), `validate.ts`, `types.ts`, módulo nativo y stub web.
- `android/`: `Audio2Mp3Module` (executor serie) → `ConversionJob` (flujo §5) → `AudioDecoder` (MediaExtractor + MediaCodec) → `NativeEncoder` (JNI de `libaudio2mp3.so`; firmas en `crates/audio2mp3-jni/src/lib.rs` del core).
- `ios/`: `Audio2Mp3Module` (DispatchQueue serie) → `ConversionJob` → `AudioDecoder` (AVAssetReader convierte el PCM; sin `pcm-convert`) → `Mp3EncoderHandle` (API C de `audio2mp3.h`).

## Comandos

En Windows los binarios de `expo-module-scripts` son bash: ejecutar con Git Bash (`bash node_modules/expo-module-scripts/bin/expo-module-test`).

- `npm test` (jest-expo: ios/android/web/node), `npx tsc --noEmit`, `npm run build`.
- `bash scripts/check-alignment.sh`: `.so` alineados a 16 KB.
- Ejemplo: `cd example && npm install && npx expo run:android`.
- Tests nativos: `cd example/android && ./gradlew :expo-audio2mp3:connectedAndroidTest`; iOS: test spec `Tests` del podspec.
- Fixtures: `scripts/make-fixtures.sh` + `scripts/run-fixtures-android.sh` (ffmpeg/ffprobe solo como herramientas).

## Convenciones

- README en dos archivos (`README.md` inglés, `README.es.md` español) con el mismo contenido y la firma al final (no tocarla).
- Comentarios y mensajes de error en español; API y README principal en inglés.
