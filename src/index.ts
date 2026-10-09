import { startConversion } from './job';
import { ConvertOptions, ConvertResult } from './types';

export {
  Audio2Mp3Error,
  type Audio2Mp3ErrorCode,
  type ConvertOptions,
  type ConvertResult,
  type Mp3Bitrate,
} from './types';

/**
 * Extrae el audio de un vídeo o audio y lo guarda como MP3.
 * Rechaza con `Audio2Mp3Error` (ver `code`).
 */
export function convertToMp3(options: ConvertOptions): Promise<ConvertResult> {
  return startConversion(options).promise;
}
