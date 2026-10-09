import Audio2Mp3Core
import Foundation

/// Envoltorio del encoder C de audio2mp3-core: `create` en init, `destroy` en deinit.
/// No es thread-safe (un hilo a la vez). Reutiliza un único buffer de salida.
final class Mp3EncoderHandle {
  let sampleRate: Int
  let channels: Int
  private let encoder: OpaquePointer
  private var output: UnsafeMutablePointer<UInt8>
  private var outputCapacity: Int

  init(sampleRate: Int, channels: Int, bitrateKbps: Int) throws {
    var created: OpaquePointer?
    let code = audio2mp3_encoder_create(
      UInt32(sampleRate), UInt8(channels), UInt16(bitrateKbps), &created)
    guard code == AUDIO2MP3_OK, let created else {
      throw Audio2Mp3Exception(
        code == AUDIO2MP3_ERR_INVALID_BITRATE ? .invalidBitrate : .encoderError,
        "No se pudo crear el encoder (\(sampleRate) Hz, \(channels) canales, \(bitrateKbps) kbps): \(code)")
    }
    self.encoder = created
    self.sampleRate = sampleRate
    self.channels = channels
    self.outputCapacity = 64 * 1024
    self.output = .allocate(capacity: outputCapacity)
  }

  deinit {
    audio2mp3_encoder_destroy(encoder)
    output.deallocate()
  }

  /// Frame Info (Xing + LAME): antes del primer encode.
  func enableInfoFrame() throws {
    try check(audio2mp3_encoder_enable_info_frame(encoder), "enable_info_frame")
  }

  /// Codifica `count` muestras S16 intercaladas. El buffer devuelto vale hasta la siguiente llamada.
  func encode(_ pcm: UnsafePointer<Int16>, count: Int) throws -> UnsafeBufferPointer<UInt8> {
    ensure(audio2mp3_encoder_max_output_size(encoder, count))
    var written = 0
    try check(
      audio2mp3_encoder_encode(encoder, pcm, count, output, outputCapacity, &written), "encode")
    return UnsafeBufferPointer(start: output, count: written)
  }

  func flush() throws -> UnsafeBufferPointer<UInt8> {
    ensure(audio2mp3_encoder_max_flush_size(encoder))
    var written = 0
    try check(audio2mp3_encoder_flush(encoder, output, outputCapacity, &written), "flush")
    return UnsafeBufferPointer(start: output, count: written)
  }

  /// Frame Info definitivo (solo tras flush); se copia sobre el inicio del archivo.
  func infoFrame() throws -> UnsafeBufferPointer<UInt8> {
    let size = audio2mp3_encoder_info_frame_size(encoder)
    guard size > 0 else { return UnsafeBufferPointer(start: output, count: 0) }
    ensure(size)
    var written = 0
    try check(audio2mp3_encoder_info_frame(encoder, output, outputCapacity, &written), "info_frame")
    return UnsafeBufferPointer(start: output, count: written)
  }

  private func ensure(_ bytes: Int) {
    guard bytes > outputCapacity else { return }
    output.deallocate()
    outputCapacity = bytes
    output = .allocate(capacity: bytes)
  }

  private func check(_ code: Int32, _ what: String) throws {
    if code != AUDIO2MP3_OK {
      throw Audio2Mp3Exception(.encoderError, "\(what) falló: \(code)")
    }
  }
}
