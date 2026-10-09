import Audio2Mp3Module from '../Audio2Mp3Module';
import { Audio2Mp3Error, convertToMp3 } from '../index';
import { startConversion, toAudio2Mp3Error } from '../job';
import { ProgressEvent } from '../types';

jest.mock('../Audio2Mp3Module', () => ({
  __esModule: true,
  default: {
    startConversion: jest.fn(),
    cancelConversion: jest.fn(),
    addListener: jest.fn(),
  },
}));

const native = Audio2Mp3Module as unknown as {
  startConversion: jest.Mock;
  cancelConversion: jest.Mock;
  addListener: jest.Mock;
};

const RESULT = {
  uri: 'file:///docs/out.mp3',
  durationMs: 1000,
  sizeBytes: 24000,
  sampleRate: 44100,
  channels: 2,
  bitrate: 192,
};

let emit: (event: ProgressEvent) => void;
const remove = jest.fn();

beforeEach(() => {
  jest.clearAllMocks();
  native.addListener.mockImplementation((_name: string, listener: typeof emit) => {
    emit = listener;
    return { remove };
  });
});

describe('convertToMp3', () => {
  it('envía las opciones con valores por defecto y devuelve el resultado nativo', async () => {
    native.startConversion.mockResolvedValue(RESULT);
    await expect(convertToMp3({ input: '/v.mp4', output: '/docs/out.mp3' })).resolves.toEqual(
      RESULT,
    );
    expect(native.startConversion).toHaveBeenCalledWith(expect.stringMatching(/^job-\d+$/), {
      input: '/v.mp4',
      output: '/docs/out.mp3',
      bitrate: 192,
      overwrite: false,
    });
    expect(remove).toHaveBeenCalled();
  });

  it('no llama al nativo si las opciones no son válidas', async () => {
    await expect(
      convertToMp3({ input: '/v.mp4', output: '/o.mp3', bitrate: 100 as never }),
    ).rejects.toMatchObject({ code: 'INVALID_BITRATE' });
    expect(native.startConversion).not.toHaveBeenCalled();
  });

  it.each(['NO_AUDIO_TRACK', 'OUTPUT_EXISTS', 'DRM_PROTECTED', 'CANCELLED', 'INSUFFICIENT_SPACE'])(
    'mapea el error nativo %s a Audio2Mp3Error',
    async code => {
      native.startConversion.mockRejectedValue(
        Object.assign(new Error(`fallo ${code}`), { code }),
      );
      const promise = convertToMp3({ input: '/v.mp4', output: '/o.mp3' });
      await expect(promise).rejects.toBeInstanceOf(Audio2Mp3Error);
      await expect(promise).rejects.toMatchObject({ code, message: `fallo ${code}` });
    },
  );
});

describe('toAudio2Mp3Error', () => {
  it('deja pasar un Audio2Mp3Error', () => {
    const error = new Audio2Mp3Error('ENCODER_ERROR', 'x');
    expect(toAudio2Mp3Error(error)).toBe(error);
  });

  it('usa DECODER_ERROR para códigos desconocidos y conserva la causa', () => {
    const original = Object.assign(new Error('raro'), { code: 'ERR_SOMETHING' });
    const mapped = toAudio2Mp3Error(original);
    expect(mapped.code).toBe('DECODER_ERROR');
    expect(mapped.message).toBe('raro');
    expect((mapped as { cause?: unknown }).cause).toBe(original);
  });
});

describe('startConversion (interno, V1.1)', () => {
  it('reenvía solo el progreso de su propio job', async () => {
    let finish!: (value: typeof RESULT) => void;
    native.startConversion.mockReturnValue(new Promise(resolve => (finish = resolve)));
    const job = startConversion({ input: '/v.mp4', output: '/o.mp3' });
    const seen: number[] = [];
    job.addProgressListener(p => seen.push(p));

    emit({ jobId: job.jobId, progress: 0.25 });
    emit({ jobId: 'job-otro', progress: 0.9 });
    emit({ jobId: job.jobId, progress: 0.5 });
    finish(RESULT);
    await job.promise;

    expect(seen).toEqual([0.25, 0.5]);
  });

  it('cancel() avisa al nativo con el jobId', async () => {
    native.startConversion.mockRejectedValue(Object.assign(new Error('x'), { code: 'CANCELLED' }));
    const job = startConversion({ input: '/v.mp4', output: '/o.mp3' });
    job.cancel();
    expect(native.cancelConversion).toHaveBeenCalledWith(job.jobId);
    await expect(job.promise).rejects.toMatchObject({ code: 'CANCELLED' });
  });

  it('cada conversión tiene un jobId distinto', () => {
    native.startConversion.mockResolvedValue(RESULT);
    const a = startConversion({ input: '/v.mp4', output: '/a.mp3' });
    const b = startConversion({ input: '/v.mp4', output: '/b.mp3' });
    expect(a.jobId).not.toBe(b.jobId);
  });
});
