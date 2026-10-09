import { Audio2Mp3Error, convertToMp3 } from '../index';

// Mock mínimo de `expo`: ts-jest no compila bien los fuentes web internos de expo.
jest.mock('expo', () => ({
  NativeModule: class {
    addListener() {
      return { remove() {} };
    }
  },
  registerWebModule: (ModuleClass: new () => unknown) => new ModuleClass(),
}));

describe('web', () => {
  it('lanza UNSUPPORTED_PLATFORM', async () => {
    const promise = convertToMp3({ input: '/v.mp4', output: '/o.mp3' });
    await expect(promise).rejects.toBeInstanceOf(Audio2Mp3Error);
    await expect(promise).rejects.toMatchObject({ code: 'UNSUPPORTED_PLATFORM' });
  });
});
