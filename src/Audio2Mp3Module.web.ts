import { NativeModule, registerWebModule } from 'expo';

import { Audio2Mp3Error, Audio2Mp3ModuleEvents, ConvertResult } from './types';

class Audio2Mp3Module extends NativeModule<Audio2Mp3ModuleEvents> {
  async startConversion(): Promise<ConvertResult> {
    throw new Audio2Mp3Error('UNSUPPORTED_PLATFORM', 'expo-audio2mp3 no está disponible en web');
  }

  cancelConversion(): void {}
}

export default registerWebModule(Audio2Mp3Module, 'ExpoAudio2Mp3');
