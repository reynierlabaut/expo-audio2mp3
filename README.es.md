# 🎧 expo-audio2mp3 - Conversor MP3 para Expo

[English](README.md) | **Español**

Módulo nativo de Expo que extrae el audio de un archivo de vídeo o audio y lo guarda como MP3. La decodificación la hace el sistema operativo (MediaExtractor + MediaCodec en Android, AVAssetReader en iOS) y la codificación [audio2mp3-core](https://github.com/reynierlabaut/audio2mp3-core), un encoder MP3 pequeño escrito en Rust que se distribuye precompilado.

```text
vídeo / audio ─► decoder del sistema ─► PCM ─► audio2mp3-core ─► MP3
```

Es solo una capa de integración: sin FFmpeg, sin decoders propios, sin C/C++ que compilar y sin necesidad de Rust.

## ✨ Características
- 🎬 **Cualquier contenedor que abra el sistema:** MP4, MOV, M4A, 3GP, WebM, MKV, MP3, WAV, OGG, FLAC, AAC...
- 🎚️ **CBR de 64 a 320 kbps** con frame Info (Xing + LAME) para duración exacta y reproducción sin huecos.
- 🔊 **Formato automático:** downmix de 5.1 a stereo y resampling a 32 / 44.1 / 48 kHz.
- 🧵 **Fuera del hilo principal y del de JS:** las conversiones van de una en una en una cola serie propia.
- 🧹 **Nunca deja un MP3 a medias:** escribe en `<output>.part` y renombra al terminar.
- 🪶 **Pequeño:** objetivo ≤ 300 KB por ABI en Android y ≤ 300 KB en iOS.

## 📋 Requisitos
- Expo SDK 54+ con la **New Architecture**.
- Una **development build** (`npx expo prebuild` / EAS Build). **Expo Go no está soportado.**
- Android minSdk 24+. Web no está soportado (rechaza con `UNSUPPORTED_PLATFORM`).

> ⚠️ **La 0.1.x es solo para Android.** La implementación de iOS está en el repositorio pero aún no se ha probado en un dispositivo; llegará en una versión posterior.

## 📦 Instalación

```bash
npx expo install expo-audio2mp3
npx expo prebuild   # o una build de EAS
```

No necesita config plugin.

## 🚀 Uso

```ts
import { File, Paths } from 'expo-file-system';
import { convertToMp3, Audio2Mp3Error } from 'expo-audio2mp3';

try {
  const result = await convertToMp3({
    input: videoUri, // p. ej. el uri devuelto por expo-document-picker
    output: new File(Paths.document, 'cancion.mp3').uri,
    bitrate: 192, // opcional, por defecto 192
    overwrite: false, // opcional, por defecto false
  });
  console.log(result.uri, result.durationMs);
} catch (error) {
  if (error instanceof Audio2Mp3Error && error.code === 'NO_AUDIO_TRACK') {
    // el vídeo no tiene audio
  }
}
```

Para guardar el MP3 en la librería de música, usa `expo-media-library` (o similar) con `result.uri`.

## 📖 API

### `convertToMp3(options): Promise<ConvertResult>`

| Opción | Tipo | Por defecto | Descripción |
|---|---|---|---|
| `input` | `string` | — | `file://`, `content://` (Android) o ruta absoluta. Vídeo o audio. |
| `output` | `string` | — | `file://` o ruta absoluta dentro del sandbox de la app. |
| `bitrate` | `64 \| 96 \| 128 \| 160 \| 192 \| 224 \| 256 \| 320` | `192` | Bitrate CBR en kbps. |
| `overwrite` | `boolean` | `false` | Si es `false` y `output` existe, rechaza con `OUTPUT_EXISTS`. |

`ConvertResult`: `uri` (`file://` del MP3), `durationMs`, `sizeBytes`, `sampleRate` (32000 \| 44100 \| 48000), `channels` (1 \| 2), `bitrate`.

### `startConversion(options): ConversionJob`

Mismas opciones, con progreso y cancelación. `convertToMp3(o)` equivale a `startConversion(o).promise`.

```ts
const job = startConversion({ input, output, bitrate: 192 });
const sub = job.addProgressListener(p => setProgress(p)); // 0.0 → 1.0, como mucho cada 100 ms / 1 %
job.cancel(); // la promesa rechaza con CANCELLED y no queda archivo parcial
const result = await job.promise;
sub.remove();
```

Si la entrada no informa su duración, no se emite progreso.

### Errores

Todo rechazo es un `Audio2Mp3Error` con su `code`:

| Código | Cuándo |
|---|---|
| `FILE_NOT_FOUND` | La entrada no existe. |
| `PERMISSION_DENIED` | No se puede leer la entrada (falta permiso o acceso security-scoped). |
| `INVALID_PATH` | Ruta vacía, relativa o mal formada; `output` es un directorio o `content://`; entrada y salida son el mismo archivo. |
| `NO_AUDIO_TRACK` | El archivo no tiene pista de audio. |
| `UNSUPPORTED_FORMAT` | El sistema no puede abrir o decodificar el archivo en este dispositivo. |
| `DRM_PROTECTED` | El archivo está protegido con DRM. |
| `DECODER_ERROR` | El decoder del sistema falló a mitad. |
| `ENCODER_ERROR` | Falló audio2mp3-core. |
| `INVALID_BITRATE` | `bitrate` no es uno de los valores permitidos. |
| `OUTPUT_EXISTS` | `output` existe y `overwrite` es `false`. |
| `OUTPUT_ERROR` | La carpeta de salida no existe o no se puede escribir, o falló la escritura. |
| `INSUFFICIENT_SPACE` | No hay espacio libre suficiente (estimado como `duración × bitrate / 8 × 1.1`). |
| `CANCELLED` | La conversión se canceló (p. ej. iOS agotó el tiempo en segundo plano). |
| `UNSUPPORTED_PLATFORM` | Llamado en web. |

### ⚠️ Los formatos soportados dependen del dispositivo

El módulo usa los decoders del sistema operativo, así que **la lista real de formatos depende del dispositivo y de la versión del sistema** (por ejemplo, WebM/Opus funciona siempre en Android pero en iOS depende de la versión). Gestiona siempre `UNSUPPORTED_FORMAT`.

## 📏 Tamaño y rendimiento

Medido en dispositivos físicos (un Android de gama media, un iPhone de hace al menos 3 años), comparando la app antes y después de añadir el módulo:

| Métrica | Objetivo | Medido |
|---|---|---|
| Aumento del APK por ABI (arm64-v8a) | ≤ 300 KB | `libaudio2mp3.so` = 299 KB (sin comprimir); app pendiente |
| Aumento del IPA | ≤ 300 KB | pendiente |
| Vídeo de 10 min → MP3 en Android gama media | ≤ 60 s | pendiente |
| Memoria adicional durante la conversión | ≤ 10 MB y constante | pendiente |

## 🛠️ Desarrollo

```bash
npm install
npm run fetch-core              # descarga audio2mp3-core (versión fijada en core-version.json)
npm test                        # jest-expo: ios, android, web y node
npm run build                   # TypeScript → build/
bash scripts/check-alignment.sh # alineación a 16 KB de los .so (necesita el NDK)
```

- `scripts/fetch-core.sh --from ../audio2mp3-core/dist` instala los binarios desde una build local del core.
- Actualizar el core = cambiar la versión y los checksums en `core-version.json`, ejecutar el script y publicar una versión del módulo.
- La app `example/` es una development build: `cd example && npm install && npx expo run:android`.
- Tests nativos: `cd example/android && ./gradlew :expo-audio2mp3:connectedAndroidTest` (Android) y el test spec `Tests` del podspec (iOS).
- Fixtures de integración: `scripts/make-fixtures.sh` crea la matriz de fixtures con ffmpeg (herramienta de desarrollo, no se distribuye) y `scripts/check-mp3.sh` valida cada MP3 con ffprobe.

```text
src/              API TypeScript (convertToMp3, tipos, validación, stub web)
android/          Kotlin: módulo Expo, decoder MediaExtractor/MediaCodec, puente JNI
ios/              Swift: módulo Expo, decoder AVAssetReader, puente C, XCTest
scripts/          fetch-core, check-alignment, fixtures y validación con ffprobe
example/          App Expo de prueba (development build)
```

## 📄 Licencia

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
