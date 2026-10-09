import { Audio2Mp3Error } from '../types';
import { validateOptions } from '../validate';

function codeOf(fn: () => unknown): string | undefined {
  try {
    fn();
  } catch (error) {
    expect(error).toBeInstanceOf(Audio2Mp3Error);
    return (error as Audio2Mp3Error).code;
  }
  return undefined;
}

describe('validateOptions', () => {
  it('aplica los valores por defecto (bitrate 192, overwrite false)', () => {
    expect(validateOptions({ input: 'file:///a/video.mp4', output: 'file:///a/out.mp3' })).toEqual({
      input: 'file:///a/video.mp4',
      output: 'file:///a/out.mp3',
      bitrate: 192,
      overwrite: false,
    });
  });

  it('respeta bitrate y overwrite explícitos', () => {
    const options = validateOptions({
      input: '/sdcard/video.mp4',
      output: '/data/out.mp3',
      bitrate: 320,
      overwrite: true,
    });
    expect(options.bitrate).toBe(320);
    expect(options.overwrite).toBe(true);
  });

  it('acepta content:// solo como entrada', () => {
    expect(
      validateOptions({ input: 'content://media/external/video/1', output: 'file:///a/out.mp3' })
        .input,
    ).toBe('content://media/external/video/1');
    expect(
      codeOf(() => validateOptions({ input: 'file:///a/v.mp4', output: 'content://media/x.mp3' })),
    ).toBe('INVALID_PATH');
  });

  it.each([0, 100, 193, 512, -1, NaN])('rechaza el bitrate %p', bitrate => {
    expect(
      codeOf(() =>
        validateOptions({ input: '/a.mp4', output: '/b.mp3', bitrate: bitrate as never }),
      ),
    ).toBe('INVALID_BITRATE');
  });

  it.each([
    ['input vacío', { input: '', output: '/b.mp3' }],
    ['input con espacios', { input: '   ', output: '/b.mp3' }],
    ['output vacío', { input: '/a.mp4', output: '' }],
    ['input relativo', { input: 'video.mp4', output: '/b.mp3' }],
    ['output relativo', { input: '/a.mp4', output: 'out.mp3' }],
    ['output directorio', { input: '/a.mp4', output: 'file:///docs/' }],
    ['mismo archivo', { input: 'file:///a/x.mp3', output: '/a/x.mp3' }],
    ['mismo archivo codificado', { input: 'file:///a/mi%20cancion.mp3', output: '/a/mi cancion.mp3' }],
  ])('rechaza %s con INVALID_PATH', (_, options) => {
    expect(codeOf(() => validateOptions(options))).toBe('INVALID_PATH');
  });

  it('rechaza options nulo', () => {
    expect(codeOf(() => validateOptions(null as never))).toBe('INVALID_PATH');
  });
});
