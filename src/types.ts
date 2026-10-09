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
  | 'FILE_NOT_FOUND'
  | 'PERMISSION_DENIED'
  | 'INVALID_PATH'
  | 'NO_AUDIO_TRACK'
  | 'UNSUPPORTED_FORMAT'
  | 'DRM_PROTECTED'
  | 'DECODER_ERROR'
  | 'ENCODER_ERROR'
  | 'INVALID_BITRATE'
  | 'OUTPUT_EXISTS'
  | 'OUTPUT_ERROR'
  | 'INSUFFICIENT_SPACE'
  | 'CANCELLED'
  | 'UNSUPPORTED_PLATFORM';

export const ERROR_CODES: readonly Audio2Mp3ErrorCode[] = [
  'FILE_NOT_FOUND',
  'PERMISSION_DENIED',
  'INVALID_PATH',
  'NO_AUDIO_TRACK',
  'UNSUPPORTED_FORMAT',
  'DRM_PROTECTED',
  'DECODER_ERROR',
  'ENCODER_ERROR',
  'INVALID_BITRATE',
  'OUTPUT_EXISTS',
  'OUTPUT_ERROR',
  'INSUFFICIENT_SPACE',
  'CANCELLED',
  'UNSUPPORTED_PLATFORM',
];

export const BITRATES: readonly Mp3Bitrate[] = [64, 96, 128, 160, 192, 224, 256, 320];

export const DEFAULT_BITRATE: Mp3Bitrate = 192;

export class Audio2Mp3Error extends Error {
  code: Audio2Mp3ErrorCode;

  constructor(code: Audio2Mp3ErrorCode, message?: string, options?: { cause?: unknown }) {
    super(message ?? code);
    this.name = 'Audio2Mp3Error';
    this.code = code;
    if (options && 'cause' in options) {
      (this as { cause?: unknown }).cause = options.cause;
    }
    // Mantiene instanceof al compilar a ES5.
    Object.setPrototypeOf(this, Audio2Mp3Error.prototype);
  }
}

/** Opciones ya validadas y con valores por defecto, tal como las recibe el módulo nativo. */
export interface NativeConvertOptions {
  input: string;
  output: string;
  bitrate: Mp3Bitrate;
  overwrite: boolean;
}

export interface ProgressEvent {
  jobId: string;
  /** 0.0 → 1.0 */
  progress: number;
}

export type Audio2Mp3ModuleEvents = {
  onProgress: (event: ProgressEvent) => void;
};

/** Conversión en curso. Interno en V1; API pública prevista para V1.1. */
export interface ConversionJob {
  jobId: string;
  promise: Promise<ConvertResult>;
  cancel(): void;
  addProgressListener(listener: (progress: number) => void): { remove(): void };
}
