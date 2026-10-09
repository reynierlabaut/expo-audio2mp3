import Audio2Mp3Module from './Audio2Mp3Module';
import { Audio2Mp3Error, ConversionJob, ConvertOptions, ERROR_CODES, Audio2Mp3ErrorCode } from './types';
import { validateOptions } from './validate';

let lastJobId = 0;

/** Convierte cualquier error (nativo o JS) en Audio2Mp3Error con su `code`. */
export function toAudio2Mp3Error(error: unknown): Audio2Mp3Error {
  if (error instanceof Audio2Mp3Error) {
    return error;
  }
  const code = (error as { code?: unknown } | null)?.code;
  const message = (error as { message?: unknown } | null)?.message;
  const text = typeof message === 'string' ? message : undefined;
  if (typeof code === 'string' && ERROR_CODES.includes(code as Audio2Mp3ErrorCode)) {
    return new Audio2Mp3Error(code as Audio2Mp3ErrorCode, text, { cause: error });
  }
  // El nativo envuelve todos sus fallos; esto solo cubre errores inesperados del puente.
  return new Audio2Mp3Error('DECODER_ERROR', text ?? String(error), { cause: error });
}

/**
 * Lanza una conversión con id propio, cancelación y progreso.
 * Interno en V1 (convertToMp3 = startConversion(...).promise); se expondrá en V1.1.
 */
export function startConversion(options: ConvertOptions): ConversionJob {
  const jobId = `job-${++lastJobId}`;
  const listeners = new Set<(progress: number) => void>();
  let started = false;
  let cancelled = false;

  const promise = (async () => {
    const nativeOptions = validateOptions(options);
    if (cancelled) {
      throw new Audio2Mp3Error('CANCELLED', 'Conversión cancelada');
    }
    const subscription = Audio2Mp3Module.addListener('onProgress', event => {
      if (event.jobId === jobId) {
        listeners.forEach(listener => listener(event.progress));
      }
    });
    try {
      started = true;
      return await Audio2Mp3Module.startConversion(jobId, nativeOptions);
    } catch (error) {
      throw toAudio2Mp3Error(error);
    } finally {
      subscription.remove();
      listeners.clear();
    }
  })();

  return {
    jobId,
    promise,
    cancel() {
      cancelled = true;
      if (started) {
        Audio2Mp3Module.cancelConversion(jobId);
      }
    },
    addProgressListener(listener) {
      listeners.add(listener);
      return { remove: () => listeners.delete(listener) };
    },
  };
}
