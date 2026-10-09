package expo.modules.audio2mp3

import java.nio.ByteBuffer

/**
 * Funciones `Java_expo_modules_audio2mp3_NativeEncoder_*` de audio2mp3-jni (libaudio2mp3.so).
 *
 * - Los ByteBuffer deben ser directos; se leen desde su dirección base, sin `position`/`limit`
 *   (salvo `inOffset` en converterProcess).
 * - PCM = S16 intercalado en orden nativo. Entrada y salida no pueden ser el mismo buffer.
 * - Un handle no es thread-safe: cada uno desde un solo hilo a la vez.
 * - Errores: códigos AUDIO2MP3_ERR_* de include/audio2mp3.h del core.
 */
internal object NativeEncoder {
  init {
    System.loadLibrary("audio2mp3")
  }

  const val FORMAT_S16 = 0
  const val FORMAT_F32 = 1

  @JvmStatic external fun version(): Int
  /** 0 si la configuración es válida; si no, código AUDIO2MP3_ERR_*. */
  @JvmStatic external fun validate(sampleRate: Int, channels: Int, bitrateKbps: Int): Int
  /** Handle opaco; 0 si la configuración no es válida (ver validate). */
  @JvmStatic external fun create(sampleRate: Int, channels: Int, bitrateKbps: Int): Long
  @JvmStatic external fun maxOutputSize(handle: Long, numSamples: Int): Int
  @JvmStatic external fun maxFlushSize(handle: Long): Int
  @JvmStatic external fun delaySamples(handle: Long): Int
  /** Bytes escritos (≥ 0) o −código de error. */
  @JvmStatic external fun encode(handle: Long, pcm: ByteBuffer, numSamples: Int, out: ByteBuffer): Int
  /** Bytes escritos (≥ 0) o −código de error. */
  @JvmStatic external fun flush(handle: Long, out: ByteBuffer): Int
  @JvmStatic external fun destroy(handle: Long)

  /** 0 o código de error. Antes del primer encode. */
  @JvmStatic external fun enableInfoFrame(handle: Long): Int
  @JvmStatic external fun infoFrameSize(handle: Long): Int
  /** Bytes escritos (≥ 0) o −código de error. Solo tras flush. */
  @JvmStatic external fun infoFrame(handle: Long, out: ByteBuffer): Int

  @JvmStatic external fun converterValidate(inRate: Int, inChannels: Int, inFormat: Int): Int
  @JvmStatic external fun converterCreate(inRate: Int, inChannels: Int, inFormat: Int): Long
  @JvmStatic external fun converterOutRate(handle: Long): Int
  @JvmStatic external fun converterOutChannels(handle: Long): Int
  /** Máximo de muestras S16 que escribe converterProcess con inBytes bytes. */
  @JvmStatic external fun converterMaxOutputSamples(handle: Long, inBytes: Int): Int
  @JvmStatic external fun converterMaxFlushSamples(handle: Long): Int
  /** Lee inBytes desde inOffset. Muestras escritas o −código. */
  @JvmStatic external fun converterProcess(handle: Long, input: ByteBuffer, inOffset: Int, inBytes: Int, out: ByteBuffer): Int
  /** Muestras escritas o −código. */
  @JvmStatic external fun converterFlush(handle: Long, out: ByteBuffer): Int
  @JvmStatic external fun converterDestroy(handle: Long)
}
