# expo-audio2mp3 — Especificación v2

## 1. Descripción

`expo-audio2mp3` es un **módulo nativo de Expo** que extrae el audio de un archivo de vídeo o audio y lo convierte a MP3.

```text
JS/TS (app Expo)
      │
      ▼
Expo Module (Kotlin / Swift)
      │
      ▼
Decoder del sistema operativo  ── Android: MediaExtractor + MediaCodec
      │                           iOS:     AVAssetReader
      ▼
PCM S16
      │
      ▼
audio2mp3-core (Rust, precompilado)
      │
      ▼
archivo .mp3
```

Es **solo una capa de integración**. No contiene encoder ni decoders propios.

## 2. Decisiones de base

| Tema | Decisión |
|---|---|
| Tipo de módulo | Expo Modules API (Kotlin + Swift) |
| Arquitectura RN | Solo New Architecture |
| Expo Go | **No soportado**: requiere development build (`npx expo prebuild` / EAS Build) |
| Web | No soportado: lanza `UNSUPPORTED_PLATFORM` |
| Versiones mínimas | Las del SDK de Expo usado (Android minSdk 24+, iOS 15.1+) |
| Encoder | `audio2mp3-core`, binarios **precompilados** y versionados |
| Rust en la app consumidora | **No necesario** (nadie compila Rust al instalar el paquete) |
| Config plugin | No necesario en V1 |
| Licencia | MIT |

## 3. Reglas fundamentales

El paquete **NO** debe contener:

- FFmpeg, GStreamer, LibAV, Symphonia;
- decoders propios de ningún formato;
- otro encoder MP3 distinto de `audio2mp3-core`;
- código C/C++ que el consumidor tenga que compilar.

La extracción y decodificación se hacen **siempre** con APIs del sistema operativo.

## 4. API pública (V1)

```typescript
export type Mp3Bitrate = 64 | 96 | 128 | 160 | 192 | 224 | 256 | 320;

export interface ConvertOptions {
  /** file://, content:// (Android) o ruta absoluta. Vídeo o audio. */
  input: string;
  /** file:// o ruta absoluta dentro del sandbox de la app. */
  output: string;
  /** Por defecto 192. */
  bitrate?: Mp3Bitrate;
  /** Por defecto false → error OUTPUT_EXISTS si ya existe. */
  overwrite?: boolean;
}

export interface ConvertResult {
  /** file:// del MP3 generado. */
  uri: string;
  durationMs: number;
  sizeBytes: number;
  sampleRate: 32000 | 44100 | 48000;
  channels: 1 | 2;
  bitrate: Mp3Bitrate;
}

export type Audio2Mp3ErrorCode =
  | "FILE_NOT_FOUND"
  | "PERMISSION_DENIED"
  | "INVALID_PATH"
  | "NO_AUDIO_TRACK"
  | "UNSUPPORTED_FORMAT"
  | "DRM_PROTECTED"
  | "DECODER_ERROR"
  | "ENCODER_ERROR"
  | "INVALID_BITRATE"
  | "OUTPUT_EXISTS"
  | "OUTPUT_ERROR"
  | "INSUFFICIENT_SPACE"
  | "CANCELLED"
  | "UNSUPPORTED_PLATFORM";

export class Audio2Mp3Error extends Error {
  code: Audio2Mp3ErrorCode;
}

export function convertToMp3(options: ConvertOptions): Promise<ConvertResult>;
```

### Ejemplo

```typescript
import * as FileSystem from "expo-file-system";
import { convertToMp3 } from "expo-audio2mp3";

const result = await convertToMp3({
  input: videoUri, // p. ej. el uri devuelto por expo-document-picker
  output: FileSystem.documentDirectory + "cancion.mp3",
});

console.log(result.uri, result.durationMs);
```

### Fuera de V1, pero la arquitectura debe permitirlo (V1.1)

```typescript
const job = startConversion({ input, output, bitrate: 192 });
const sub = job.addProgressListener((p) => console.log(p)); // 0.0 → 1.0
job.cancel();
const result = await job.promise; // rechaza con CANCELLED si se canceló
```

Para que esto sea posible sin reescribir nada, **V1 ya implementa internamente**:

- un `jobId` por conversión;
- un registro nativo `jobId → flag atómico de cancelación`, consultado entre chunks;
- cálculo del progreso (`posición PCM / duración de la pista`);
- emisión de progreso limitada (como máximo cada 100 ms o cada 1 %), aunque en V1 no se exponga.

`convertToMp3` en V1 es simplemente `startConversion(...).promise`.

## 5. Flujo común (ambas plataformas)

1. Validar opciones (bitrate, rutas, `overwrite`).
2. Resolver y comprobar la entrada (existe, es legible, no es un directorio).
3. Comprobar la salida:
   - el directorio padre existe y se puede escribir;
   - si el archivo existe y `overwrite = false` → `OUTPUT_EXISTS`;
   - espacio libre ≥ estimación (`duración × bitrate / 8 × 1.1`), si no → `INSUFFICIENT_SPACE`.
4. Abrir la entrada y seleccionar la **primera pista de audio**. Si no hay → `NO_AUDIO_TRACK`.
5. Decodificar a PCM S16 interleaved, 1–2 canales, 32/44.1/48 kHz (ver detalles por plataforma).
6. Crear el encoder con la tasa y canales **reales** de salida del decoder/convertidor.
7. Bucle: PCM chunk → `encode` → escribir bytes en `<output>.part`.
8. `flush` → escribir → cerrar el archivo.
9. Renombrar `<output>.part` → `<output>` (si `overwrite`, reemplazar).
10. Resolver la promesa con `ConvertResult`.

Ante **cualquier error o cancelación**: liberar el decoder y el encoder, borrar `<output>.part` y rechazar con el código adecuado. Nunca debe quedar un MP3 a medias con el nombre final.

### Memoria

- Buffers de tamaño fijo reutilizados durante toda la conversión (PCM ≈ 64 KB, salida = `max_output_size`).
- La memoria no debe crecer con la duración del archivo.

### Concurrencia

- Las conversiones se ejecutan en una **cola serie** dedicada (una a la vez). Las llamadas extra esperan su turno.
- Nunca se trabaja en el hilo principal ni en el hilo de JS.

## 6. Android

### Lenguaje y threading

- Kotlin, `AsyncFunction` del Expo Module que delega el trabajo a un executor serie propio (o `Dispatchers.IO` con un mutex).

### Entrada

- `content://` → `MediaExtractor.setDataSource(context, uri, null)`.
- `file://` o ruta → `setDataSource(path)`.
- `SecurityException` → `PERMISSION_DENIED`.
- Contenedores habituales que el sistema suele abrir: MP4/M4A, 3GP, WebM, MKV, MP3, WAV, OGG, FLAC, AAC/ADTS. **La compatibilidad real depende del dispositivo**; la documentación no debe prometer formatos.

### Decodificación

1. Recorrer las pistas y elegir la primera con `MIME` que empiece por `audio/`.
2. `MediaCodec.createDecoderByType(mime)`; si falla → `UNSUPPORTED_FORMAT`.
3. Bucle síncrono de input/output buffers.
4. **Usar siempre el formato de salida del decoder** (`INFO_OUTPUT_FORMAT_CHANGED`), no el de la pista. Ejemplo: en HE-AAC la pista dice 22 050 Hz y el decoder entrega 44 100.
5. Leer `KEY_SAMPLE_RATE`, `KEY_CHANNEL_COUNT` y `KEY_PCM_ENCODING` (por defecto PCM 16-bit; puede ser `ENCODING_PCM_FLOAT`).
6. Errores de `MediaCodec` → `DECODER_ERROR`.

### Conversión de PCM

Siempre a través del `PcmConverter` del core (feature `pcm-convert`):

```text
bytes del decoder (S16 o F32, N canales, X Hz)
      ↓  PcmConverter (Rust)
S16, 1–2 canales, 32/44.1/48 kHz
      ↓  Mp3Encoder (Rust)
MP3
```

Si la entrada ya es S16 con 1–2 canales y 32/44.1/48 kHz, el converter no modifica las muestras (sin coste de resampling).

### Puente nativo

- Clase Kotlin `NativeEncoder` con métodos `external` que corresponden a las funciones `Java_…` de `audio2mp3-jni`.
- Datos en **`ByteBuffer.allocateDirect`**, reservados una vez y reutilizados: no hay copias de arrays entre Kotlin y Rust.
- `System.loadLibrary("audio2mp3")`.

### Salida

- `FileOutputStream` sobre `<output>.part` (V1 solo admite salida a ruta o `file://` del sandbox).
- `IOException` por disco lleno → `INSUFFICIENT_SPACE`; otras → `OUTPUT_ERROR`.

### Binarios

```text
android/src/main/jniLibs/
├── arm64-v8a/libaudio2mp3.so
├── armeabi-v7a/libaudio2mp3.so
└── x86_64/libaudio2mp3.so
```

- Alineados a **16 KB** (verificar en CI con `zipalign -c -P 16` o `llvm-readelf`).
- El AAB de Play reparte solo la ABI de cada dispositivo.

## 7. iOS

### Lenguaje y threading

- Swift, `AsyncFunction` del Expo Module, con el trabajo en una `DispatchQueue` serie propia.

### Entrada

- `AVURLAsset(url:)`.
- URLs fuera del sandbox (del selector de documentos): `startAccessingSecurityScopedResource()` / `stop…` en `defer`.
- `asset.hasProtectedContent == true` → `DRM_PROTECTED`.

### Decodificación

- `AVAssetReader` + `AVAssetReaderTrackOutput` sobre la primera pista de audio.
- Ningún track de audio → `NO_AUDIO_TRACK`.
- `outputSettings` para que **iOS haga la conversión**:

```swift
[
  AVFormatIDKey: kAudioFormatLinearPCM,
  AVLinearPCMBitDepthKey: 16,
  AVLinearPCMIsFloatKey: false,
  AVLinearPCMIsBigEndianKey: false,
  AVLinearPCMIsNonInterleaved: false,
  AVSampleRateKey: targetRate,          // regla de tasa de §9 del core
  AVNumberOfChannelsKey: min(srcChannels, 2),
  // si srcChannels > 2: AVChannelLayoutKey con layout stereo
]
```

- Así iOS entrega PCM listo y **no se usa `pcm-convert`** (el XCFramework es más pequeño).
- `reader.status == .failed` → `DECODER_ERROR` (o `UNSUPPORTED_FORMAT` si falla al iniciar).

### Puente nativo

- `Audio2Mp3Core.xcframework` (staticlib) con `audio2mp3.h` + `module.modulemap`; se importa desde Swift con `import Audio2Mp3Core`.
- Envoltorio Swift `Mp3EncoderHandle` (clase) que llama a `create` en `init` y a `destroy` en `deinit`.

### Salida

- `FileHandle` sobre `<output>.part`; al final, `FileManager.replaceItemAt` / `moveItem`.

### Background

- Envolver la conversión en `UIApplication.beginBackgroundTask` para que no se corte si el usuario sale de la app un momento.
- Si el sistema expira la tarea → cancelar limpiamente → `CANCELLED`.

### Binarios

- Declarados en el podspec: `s.vendored_frameworks = "Audio2Mp3Core.xcframework"`.
- El XCFramework separa device y simulador, así que el simulador no entra en el IPA final.

## 8. Integración de `audio2mp3-core`

- Versión fijada en `core-version.json` (`version` + `sha256` de cada artefacto).
- `scripts/fetch-core.sh` descarga el release, verifica los checksums y copia:
  - `.so` → `android/src/main/jniLibs/…`;
  - `.xcframework` → `ios/`.
- Los binarios **se incluyen en el paquete npm**. El consumidor solo hace `npx expo install expo-audio2mp3`.
- Actualizar el core = cambiar la versión en `core-version.json` + ejecutar el script + publicar una versión del módulo.

## 9. Estructura del repositorio

Basada en `npx create-expo-module`:

```text
expo-audio2mp3/
├── package.json
├── expo-module.config.json
├── tsconfig.json
├── README.md
├── LICENSE
├── CHANGELOG.md
├── core-version.json
├── scripts/
│   └── fetch-core.sh
├── src/
│   ├── index.ts                 # convertToMp3, tipos, Audio2Mp3Error
│   ├── Audio2Mp3Module.ts       # requireNativeModule
│   ├── Audio2Mp3Module.web.ts   # UNSUPPORTED_PLATFORM
│   ├── types.ts
│   └── validate.ts
├── android/
│   ├── build.gradle
│   └── src/main/
│       ├── java/expo/modules/audio2mp3/
│       │   ├── Audio2Mp3Module.kt
│       │   ├── ConversionJob.kt
│       │   ├── AudioDecoder.kt
│       │   ├── NativeEncoder.kt
│       │   └── Errors.kt
│       └── jniLibs/…
├── ios/
│   ├── ExpoAudio2Mp3.podspec
│   ├── Audio2Mp3Module.swift
│   ├── ConversionJob.swift
│   ├── AudioDecoder.swift
│   ├── Mp3EncoderHandle.swift
│   ├── Errors.swift
│   └── Audio2Mp3Core.xcframework/
└── example/                     # app Expo de prueba (dev build)
```

## 10. Tests

### TypeScript (jest-expo)

- Validación de opciones (bitrate inválido, rutas vacías).
- Mapeo de errores nativos a `Audio2Mp3Error` con su `code`.
- Valores por defecto (`bitrate = 192`, `overwrite = false`).
- Web lanza `UNSUPPORTED_PLATFORM`.

### Android (instrumentados) e iOS (XCTest)

- Selección de pista y caso sin pista de audio.
- Formato de salida del decoder y conversión a S16.
- Ciclo de vida del encoder (create, encode, flush, destroy sin fugas).
- `.part` borrado al fallar; `OUTPUT_EXISTS`; `overwrite = true`.
- Cancelación interna (aunque V1 no la exponga).

### Fixtures de integración

| Archivo | Esperado |
|---|---|
| MP4 H.264 + AAC 44.1 kHz stereo | OK |
| MP4 + AAC 48 kHz stereo | OK (48 kHz, sin resampling) |
| MP4 + HE-AAC | OK (tasa del formato de salida) |
| MOV (iPhone) | OK |
| MP4 con AAC 5.1 | OK, stereo |
| WebM + Opus 48 kHz | OK en Android; en iOS según la versión del sistema |
| M4A, MP3, WAV 16 kHz mono, FLAC 96 kHz | OK (con resampling donde corresponda) |
| Vídeo sin audio | `NO_AUDIO_TRACK` |
| Archivo corrupto / texto renombrado | `UNSUPPORTED_FORMAT` o `DECODER_ERROR` |
| Ruta inexistente | `FILE_NOT_FOUND` |

Cada MP3 generado se valida con `ffprobe` en CI (sample rate, canales, bitrate y duración ±1 frame).

### Archivos largos

- 10 s, 1 min, 10 min, 30 min, 1 h.
- La memoria del proceso no debe crecer de forma proporcional a la duración.

## 11. Rendimiento y tamaño

Medir por separado **decoder / converter / encoder / escritura** en dispositivos físicos (un Android de gama media, un iPhone de hace al menos 3 años).

| Métrica | Objetivo |
|---|---|
| Aumento del APK por ABI (arm64-v8a) | ≤ 300 KB |
| Aumento del IPA | ≤ 300 KB |
| Vídeo de 10 min → MP3 en Android gama media | ≤ 60 s |
| Memoria adicional durante la conversión | ≤ 10 MB y constante |

Comparar el tamaño de la app **antes y después** de añadir el módulo y documentarlo en el README.

## 12. Fuera del alcance de V1

- Progreso y cancelación públicos (V1.1, ya preparados internamente).
- Escribir directamente en `content://` o en la librería de música. La app usa `expo-media-library` o similar con el MP3 resultante.
- Metadata ID3 (título, artista, carátula). Candidato fuerte para V1.2 en este repo, no en el core.
- Recorte (inicio/fin), selección de pista concreta, VBR, opciones de sample rate o canales.
- Expo Go, web, arquitectura antigua.

## 13. Criterios de aceptación V1

- [ ] Funciona en development build de Expo en Android e iOS (dispositivos físicos).
- [ ] Convierte todos los fixtures "OK" de §10 y devuelve los errores esperados en el resto.
- [ ] No bloquea el hilo de JS ni el principal (la UI sigue fluida durante una conversión de 30 min).
- [ ] Nunca deja archivos `.part` ni MP3 incompletos.
- [ ] Usa `audio2mp3-core` precompilado; el consumidor no necesita Rust ni compilar C/C++.
- [ ] `.so` alineados a 16 KB.
- [ ] Sin FFmpeg, Symphonia ni ningún otro encoder/decoder de terceros.
- [ ] Objetivos de §11 medidos y documentados.
- [ ] README con instalación, ejemplo, tabla de errores y aviso de que los formatos soportados dependen del sistema.

## 14. Regla principal

```text
vídeo / audio ─► decoder del sistema ─► PCM ─► audio2mp3-core ─► MP3
```

El módulo debe seguir siendo pequeño, especializado y fácil de integrar. Cualquier función que no esté en esta spec se discute y se especifica antes de implementarla.
