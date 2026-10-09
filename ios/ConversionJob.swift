import AVFoundation
import UIKit

let BITRATES: Set<Int> = [64, 96, 128, 160, 192, 224, 256, 320]

struct ConvertParams {
  let input: String
  let output: String
  let bitrate: Int
  let overwrite: Bool
}

final class CancellationToken {
  private let lock = NSLock()
  private var cancelled = false

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }
}

/// Registro `jobId → flag atómico de cancelación`, consultado entre chunks.
final class JobRegistry {
  private let lock = NSLock()
  private var jobs: [String: CancellationToken] = [:]
  /// Cancelaciones que llegan antes de que la conversión se registre.
  private var cancelledEarly: Set<String> = []

  func register(_ jobId: String) -> CancellationToken {
    lock.lock()
    defer { lock.unlock() }
    let token = CancellationToken()
    if cancelledEarly.remove(jobId) != nil {
      token.cancel()
    }
    jobs[jobId] = token
    return token
  }

  func cancel(_ jobId: String) {
    lock.lock()
    defer { lock.unlock() }
    if let token = jobs[jobId] {
      token.cancel()
    } else {
      cancelledEarly.insert(jobId)
    }
  }

  func unregister(_ jobId: String) {
    lock.lock()
    jobs.removeValue(forKey: jobId)
    lock.unlock()
  }

  func cancelAll() {
    lock.lock()
    jobs.values.forEach { $0.cancel() }
    lock.unlock()
  }
}

/// Mantiene viva la conversión si el usuario sale un momento de la app.
/// Si el sistema expira la tarea, se cancela la conversión (→ CANCELLED).
final class BackgroundTask {
  private var identifier: UIBackgroundTaskIdentifier = .invalid

  init(onExpire: @escaping () -> Void) {
    Self.onMain {
      identifier = UIApplication.shared.beginBackgroundTask(withName: "expo-audio2mp3") { [weak self] in
        onExpire()
        self?.endOnMain()
      }
    }
  }

  func end() {
    Self.onMain { endOnMain() }
  }

  /// UIApplication solo desde el hilo principal (sin `sync` si ya estamos en él).
  private static func onMain(_ body: () -> Void) {
    if Thread.isMainThread {
      body()
    } else {
      DispatchQueue.main.sync(execute: body)
    }
  }

  private func endOnMain() {
    guard identifier != .invalid else { return }
    UIApplication.shared.endBackgroundTask(identifier)
    identifier = .invalid
  }
}

/// Una conversión completa (flujo común de la spec, §5). Se ejecuta en la cola serie del módulo.
/// Ante cualquier error o cancelación libera decoder y encoder y borra `<output>.part`.
final class ConversionJob {
  private let params: ConvertParams
  private let token: CancellationToken
  private let onProgress: (Double) -> Void
  private let fileManager = FileManager.default

  init(params: ConvertParams, token: CancellationToken, onProgress: @escaping (Double) -> Void) {
    self.params = params
    self.token = token
    self.onProgress = onProgress
  }

  func run() throws -> [String: Any] {
    // 1. Opciones (JS ya las valida; se repite por si llaman al nativo directamente).
    guard BITRATES.contains(params.bitrate) else {
      throw Audio2Mp3Exception(.invalidBitrate, "Bitrate no válido: \(params.bitrate)")
    }
    // 2. Entrada (URLs del selector de documentos: acceso security-scoped).
    let inputURL = try resolve(params.input)
    let accessing = inputURL.startAccessingSecurityScopedResource()
    defer {
      if accessing { inputURL.stopAccessingSecurityScopedResource() }
    }
    try checkInput(inputURL)
    // 3. Salida.
    let outputURL = try resolve(params.output)
    try checkOutput(outputURL, input: inputURL)
    try checkCancelled()

    let task = BackgroundTask { [token] in token.cancel() }
    defer { task.end() }

    let partURL = URL(fileURLWithPath: outputURL.path + ".part")
    do {
      return try convert(inputURL, to: outputURL, part: partURL)
    } catch {
      try? fileManager.removeItem(at: partURL)
      throw error
    }
  }

  private func convert(_ inputURL: URL, to outputURL: URL, part partURL: URL) throws -> [String: Any] {
    // 4-5. Primera pista de audio, decodificada a PCM S16 por iOS.
    let decoder = try AudioDecoder(asset: AVURLAsset(url: inputURL))
    try checkSpace(outputURL, durationSeconds: decoder.durationSeconds)
    try decoder.start()

    // 6. Encoder con la tasa y canales reales de salida.
    let encoder = try Mp3EncoderHandle(
      sampleRate: decoder.outputSampleRate, channels: decoder.outputChannels,
      bitrateKbps: params.bitrate)
    try encoder.enableInfoFrame()

    guard fileManager.createFile(atPath: partURL.path, contents: nil) else {
      throw Audio2Mp3Exception(.outputError, "No se pudo crear \(partURL.path)")
    }
    let handle: FileHandle
    do {
      handle = try FileHandle(forWritingTo: partURL)
    } catch {
      throw outputException(error)
    }
    defer { try? handle.close() }

    // 7. PCM → encode → <output>.part
    var samplesPerChannel: Int64 = 0
    var lastProgress = 0.0
    var lastProgressAt = 0.0
    let duration = decoder.durationSeconds
    try decoder.read(isCancelled: { token.isCancelled }) { pcm, count, seconds in
      try write(encoder.encode(pcm, count: count), to: handle)
      samplesPerChannel += Int64(count / decoder.outputChannels)
      // Progreso = posición PCM / duración; como mucho cada 100 ms y cada 1 %.
      guard duration > 0 else { return }
      let progress = min(max(seconds / duration, 0), 1)
      let now = ProcessInfo.processInfo.systemUptime
      if progress - lastProgress >= 0.01 && now - lastProgressAt >= 0.1 {
        lastProgress = progress
        lastProgressAt = now
        onProgress(progress)
      }
    }
    try checkCancelled()

    // 8. flush → frame Info definitivo al inicio → cerrar.
    try write(encoder.flush(), to: handle)
    let info = try encoder.infoFrame()
    if info.count > 0 {
      do {
        try handle.seek(toOffset: 0)
      } catch {
        throw outputException(error)
      }
      try write(info, to: handle)
    }
    do {
      try handle.synchronize()
      try handle.close()
    } catch {
      throw outputException(error)
    }
    try checkCancelled()

    // 9. Renombrar.
    do {
      if fileManager.fileExists(atPath: outputURL.path) {
        guard params.overwrite else {
          throw Audio2Mp3Exception(.outputExists, "Ya existe \(outputURL.path)")
        }
        _ = try fileManager.replaceItemAt(outputURL, withItemAt: partURL)
      } else {
        try fileManager.moveItem(at: partURL, to: outputURL)
      }
    } catch let error as Audio2Mp3Exception {
      throw error
    } catch {
      throw Audio2Mp3Exception(.outputError, "No se pudo renombrar el MP3: \(error.localizedDescription)")
    }
    onProgress(1.0)

    // 10. Resultado.
    let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path)
    let size = (attributes?[.size] as? NSNumber)?.doubleValue ?? 0
    return [
      "uri": outputURL.absoluteString,
      "durationMs": Double(samplesPerChannel * 1000 / Int64(decoder.outputSampleRate)),
      "sizeBytes": size,
      "sampleRate": decoder.outputSampleRate,
      "channels": decoder.outputChannels,
      "bitrate": params.bitrate,
    ]
  }

  private func write(_ bytes: UnsafeBufferPointer<UInt8>, to handle: FileHandle) throws {
    guard let base = bytes.baseAddress, bytes.count > 0 else { return }
    let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: bytes.count, deallocator: .none)
    do {
      try handle.write(contentsOf: data)
    } catch {
      throw outputException(error)
    }
  }

  private func checkCancelled() throws {
    if token.isCancelled {
      throw Audio2Mp3Exception(.cancelled, "Conversión cancelada")
    }
  }

  /// file:// o ruta absoluta (content:// es solo de Android).
  private func resolve(_ raw: String) throws -> URL {
    if raw.hasPrefix("file://") {
      let url =
        URL(string: raw)
        ?? raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
      guard let url, url.isFileURL else {
        throw Audio2Mp3Exception(.invalidPath, "Ruta no válida: \(raw)")
      }
      return url.standardizedFileURL
    }
    if raw.hasPrefix("/") {
      return URL(fileURLWithPath: raw).standardizedFileURL
    }
    throw Audio2Mp3Exception(.invalidPath, "Ruta no válida: \(raw)")
  }

  private func checkInput(_ url: URL) throws {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      throw Audio2Mp3Exception(.fileNotFound, "No existe la entrada: \(url.path)")
    }
    if isDirectory.boolValue {
      throw Audio2Mp3Exception(.invalidPath, "La entrada es un directorio: \(url.path)")
    }
    guard fileManager.isReadableFile(atPath: url.path) else {
      throw Audio2Mp3Exception(.permissionDenied, "Sin permiso para leer \(url.path)")
    }
  }

  private func checkOutput(_ url: URL, input: URL) throws {
    var isDirectory: ObjCBool = false
    let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
    if exists && isDirectory.boolValue {
      throw Audio2Mp3Exception(.invalidPath, "La salida es un directorio: \(url.path)")
    }
    if url.resolvingSymlinksInPath().path == input.resolvingSymlinksInPath().path {
      throw Audio2Mp3Exception(.invalidPath, "La entrada y la salida son el mismo archivo")
    }
    let parent = url.deletingLastPathComponent()
    var parentIsDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory),
      parentIsDirectory.boolValue
    else {
      throw Audio2Mp3Exception(.outputError, "No existe el directorio \(parent.path)")
    }
    guard fileManager.isWritableFile(atPath: parent.path) else {
      throw Audio2Mp3Exception(.outputError, "No se puede escribir en \(parent.path)")
    }
    if exists && !params.overwrite {
      throw Audio2Mp3Exception(.outputExists, "Ya existe \(url.path)")
    }
  }

  /// Espacio libre ≥ duración × bitrate / 8 × 1.1. Sin duración conocida no se comprueba.
  private func checkSpace(_ output: URL, durationSeconds: Double) throws {
    guard durationSeconds > 0 else { return }
    let estimate = durationSeconds * Double(params.bitrate) * 1000 / 8 * 1.1
    let parent = output.deletingLastPathComponent()
    guard
      let free = try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        .volumeAvailableCapacityForImportantUsage
    else { return }
    if Double(free) < estimate {
      throw Audio2Mp3Exception(
        .insufficientSpace, "Espacio insuficiente: hacen falta ~\(Int64(estimate)) bytes")
    }
  }
}
