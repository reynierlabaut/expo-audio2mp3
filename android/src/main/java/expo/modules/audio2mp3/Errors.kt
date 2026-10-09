package expo.modules.audio2mp3

import java.io.IOException

/** Mismos códigos que `Audio2Mp3ErrorCode` en src/types.ts. */
enum class ErrorCode {
  FILE_NOT_FOUND,
  PERMISSION_DENIED,
  INVALID_PATH,
  NO_AUDIO_TRACK,
  UNSUPPORTED_FORMAT,
  DRM_PROTECTED,
  DECODER_ERROR,
  ENCODER_ERROR,
  INVALID_BITRATE,
  OUTPUT_EXISTS,
  OUTPUT_ERROR,
  INSUFFICIENT_SPACE,
  CANCELLED,
}

class Audio2Mp3Exception(
  val code: ErrorCode,
  message: String,
  cause: Throwable? = null,
) : Exception(message, cause)

internal fun fail(code: ErrorCode, message: String, cause: Throwable? = null): Nothing =
  throw Audio2Mp3Exception(code, message, cause)

/** Disco lleno (ENOSPC) frente a cualquier otro error de escritura. */
internal fun IOException.toOutputException(): Audio2Mp3Exception {
  val text = generateSequence<Throwable>(this) { it.cause }.mapNotNull { it.message }.joinToString(" ")
  val full = text.contains("ENOSPC") || text.contains("No space left", ignoreCase = true)
  return Audio2Mp3Exception(
    if (full) ErrorCode.INSUFFICIENT_SPACE else ErrorCode.OUTPUT_ERROR,
    message ?: "Error al escribir el MP3",
    this,
  )
}
