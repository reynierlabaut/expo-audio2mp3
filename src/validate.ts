import {
  Audio2Mp3Error,
  BITRATES,
  ConvertOptions,
  DEFAULT_BITRATE,
  Mp3Bitrate,
  NativeConvertOptions,
} from './types';

const isFileUri = (path: string) => path.startsWith('file://');
const isContentUri = (path: string) => path.startsWith('content://');
const isAbsolutePath = (path: string) => path.startsWith('/');

/** Quita `file://` y normaliza para comparar entrada y salida. */
function comparablePath(path: string): string {
  const raw = isFileUri(path) ? path.slice('file://'.length) : path;
  try {
    return decodeURI(raw);
  } catch {
    return raw;
  }
}

/** Valida las opciones (paso 1 del flujo) y aplica los valores por defecto. */
export function validateOptions(options: ConvertOptions): NativeConvertOptions {
  if (options == null || typeof options !== 'object') {
    throw new Audio2Mp3Error('INVALID_PATH', 'options es obligatorio');
  }
  const { input, output } = options;
  const bitrate = options.bitrate ?? DEFAULT_BITRATE;
  const overwrite = options.overwrite ?? false;

  if (typeof input !== 'string' || input.trim() === '') {
    throw new Audio2Mp3Error('INVALID_PATH', 'input está vacío');
  }
  if (!isFileUri(input) && !isContentUri(input) && !isAbsolutePath(input)) {
    throw new Audio2Mp3Error(
      'INVALID_PATH',
      `input debe ser file://, content:// o una ruta absoluta: ${input}`,
    );
  }

  if (typeof output !== 'string' || output.trim() === '') {
    throw new Audio2Mp3Error('INVALID_PATH', 'output está vacío');
  }
  if (!isFileUri(output) && !isAbsolutePath(output)) {
    throw new Audio2Mp3Error(
      'INVALID_PATH',
      `output debe ser file:// o una ruta absoluta: ${output}`,
    );
  }
  if (output.endsWith('/')) {
    throw new Audio2Mp3Error('INVALID_PATH', `output es un directorio: ${output}`);
  }
  if (comparablePath(input) === comparablePath(output)) {
    throw new Audio2Mp3Error('INVALID_PATH', 'input y output son el mismo archivo');
  }

  if (!BITRATES.includes(bitrate as Mp3Bitrate)) {
    throw new Audio2Mp3Error(
      'INVALID_BITRATE',
      `bitrate debe ser uno de ${BITRATES.join(', ')} (recibido: ${String(bitrate)})`,
    );
  }

  if (typeof overwrite !== 'boolean') {
    throw new Audio2Mp3Error('INVALID_PATH', 'overwrite debe ser booleano');
  }

  return { input, output, bitrate, overwrite };
}
