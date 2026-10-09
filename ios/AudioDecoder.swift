import AVFoundation

/// Lee la primera pista de audio con AVAssetReader. iOS hace la conversión:
/// entrega PCM S16 intercalado, 1–2 canales, 32/44.1/48 kHz (no se usa pcm-convert).
final class AudioDecoder {
  let outputSampleRate: Int
  let outputChannels: Int
  /// Duración en segundos; 0 si no se conoce.
  let durationSeconds: Double

  private let reader: AVAssetReader
  private let output: AVAssetReaderTrackOutput
  private var scratch: UnsafeMutableRawPointer?
  private var scratchCapacity = 0

  init(asset: AVURLAsset) throws {
    if asset.hasProtectedContent {
      throw Audio2Mp3Exception(.drmProtected, "El archivo está protegido con DRM")
    }
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw Audio2Mp3Exception(.noAudioTrack, "El archivo no tiene pista de audio")
    }
    let (sourceRate, sourceChannels) = Self.sourceFormat(of: track)
    outputSampleRate = Self.targetRate(for: sourceRate)
    outputChannels = max(1, min(sourceChannels, 2))

    var settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
      AVSampleRateKey: outputSampleRate,
      AVNumberOfChannelsKey: outputChannels,
    ]
    if sourceChannels > 2 {
      var layout = AudioChannelLayout()
      layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
      settings[AVChannelLayoutKey] = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }

    do {
      reader = try AVAssetReader(asset: asset)
    } catch {
      throw Audio2Mp3Exception(.unsupportedFormat, "El sistema no puede abrir el archivo: \(error.localizedDescription)")
    }
    output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
      throw Audio2Mp3Exception(.unsupportedFormat, "El sistema no puede decodificar la pista de audio")
    }
    reader.add(output)

    let seconds = CMTimeGetSeconds(asset.duration)
    durationSeconds = seconds.isFinite && seconds > 0 ? seconds : 0
  }

  deinit {
    if reader.status == .reading {
      reader.cancelReading()
    }
    scratch?.deallocate()
  }

  func start() throws {
    guard reader.startReading() else {
      throw Audio2Mp3Exception(
        .unsupportedFormat,
        "El sistema no puede decodificar el archivo: \(reader.error?.localizedDescription ?? "desconocido")")
    }
  }

  /// Entrega cada bloque de PCM (puntero, muestras intercaladas, segundo de presentación).
  /// El puntero solo es válido durante la llamada.
  func read(
    isCancelled: () -> Bool,
    _ body: (UnsafePointer<Int16>, Int, Double) throws -> Void
  ) throws {
    while true {
      if isCancelled() {
        reader.cancelReading()
        throw Audio2Mp3Exception(.cancelled, "Conversión cancelada")
      }
      let more: Bool = try autoreleasepool {
        guard let sample = output.copyNextSampleBuffer() else { return false }
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return true }
        let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
        try withPcm(block) { pcm, count in try body(pcm, count, seconds.isFinite ? seconds : 0) }
        return true
      }
      if !more { break }
    }
    switch reader.status {
    case .completed:
      return
    case .cancelled:
      throw Audio2Mp3Exception(.cancelled, "Conversión cancelada")
    default:
      throw Audio2Mp3Exception(
        .decoderError, "Error del decoder: \(reader.error?.localizedDescription ?? "desconocido")")
    }
  }

  /// Sin copia si el bloque es contiguo y está alineado; si no, se copia a un buffer reutilizado.
  private func withPcm(_ block: CMBlockBuffer, _ body: (UnsafePointer<Int16>, Int) throws -> Void) throws {
    var lengthAtOffset = 0
    var total = 0
    var pointer: UnsafeMutablePointer<CChar>?
    let status = CMBlockBufferGetDataPointer(
      block, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &total,
      dataPointerOut: &pointer)
    let count = total / MemoryLayout<Int16>.size
    guard count > 0 else { return }

    if status == kCMBlockBufferNoErr, let pointer, lengthAtOffset == total,
      Int(bitPattern: pointer) % MemoryLayout<Int16>.alignment == 0
    {
      try pointer.withMemoryRebound(to: Int16.self, capacity: count) { try body($0, count) }
      return
    }

    if total > scratchCapacity {
      scratch?.deallocate()
      scratch = .allocate(byteCount: total, alignment: MemoryLayout<Int16>.alignment)
      scratchCapacity = total
    }
    guard let scratch,
      CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: total, destination: scratch)
        == kCMBlockBufferNoErr
    else {
      throw Audio2Mp3Exception(.decoderError, "No se pudo leer el bloque de audio")
    }
    try body(UnsafePointer(scratch.assumingMemoryBound(to: Int16.self)), count)
  }

  private static func sourceFormat(of track: AVAssetTrack) -> (Double, Int) {
    guard let description = track.formatDescriptions.first,
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
        description as! CMAudioFormatDescription)?.pointee
    else {
      return (0, 2)
    }
    return (asbd.mSampleRate, Int(asbd.mChannelsPerFrame))
  }

  /// Regla de tasa de salida del core (§9 de la spec de audio2mp3-core).
  static func targetRate(for rate: Double) -> Int {
    switch Int(rate.rounded()) {
    case 32_000, 44_100, 48_000: return Int(rate.rounded())
    case 8_000, 16_000: return 32_000
    case 11_025, 22_050, 88_200, 176_400: return 44_100
    default: return 48_000
    }
  }
}
