import { NativeModule, requireNativeModule } from 'expo';

import { Audio2Mp3ModuleEvents, ConvertResult, NativeConvertOptions } from './types';

export declare class Audio2Mp3NativeModule extends NativeModule<Audio2Mp3ModuleEvents> {
  /** Encola una conversión. Resuelve al terminar; rechaza con un código de Audio2Mp3ErrorCode. */
  startConversion(jobId: string, options: NativeConvertOptions): Promise<ConvertResult>;
  /** Marca la conversión como cancelada (también si aún está en cola). */
  cancelConversion(jobId: string): void;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<Audio2Mp3NativeModule>('ExpoAudio2Mp3');
