import Foundation

/// Mismos códigos que `Audio2Mp3ErrorCode` en src/types.ts.
enum ErrorCode: String {
  case fileNotFound = "FILE_NOT_FOUND"
  case permissionDenied = "PERMISSION_DENIED"
  case invalidPath = "INVALID_PATH"
  case noAudioTrack = "NO_AUDIO_TRACK"
  case unsupportedFormat = "UNSUPPORTED_FORMAT"
  case drmProtected = "DRM_PROTECTED"
  case decoderError = "DECODER_ERROR"
  case encoderError = "ENCODER_ERROR"
  case invalidBitrate = "INVALID_BITRATE"
  case outputExists = "OUTPUT_EXISTS"
  case outputError = "OUTPUT_ERROR"
  case insufficientSpace = "INSUFFICIENT_SPACE"
  case cancelled = "CANCELLED"
}

struct Audio2Mp3Exception: Error, CustomStringConvertible {
  let code: ErrorCode
  let message: String

  init(_ code: ErrorCode, _ message: String) {
    self.code = code
    self.message = message
  }

  var description: String { "\(code.rawValue): \(message)" }
}

/// Disco lleno frente a cualquier otro error de escritura.
func outputException(_ error: Error) -> Audio2Mp3Exception {
  let nsError = error as NSError
  let full =
    (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)
    || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC))
  return Audio2Mp3Exception(full ? .insufficientSpace : .outputError, nsError.localizedDescription)
}
