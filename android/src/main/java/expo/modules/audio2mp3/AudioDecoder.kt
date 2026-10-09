package expo.modules.audio2mp3

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.nio.ByteBuffer

internal sealed class InputSource {
  data class Content(val uri: Uri) : InputSource()
  data class Path(val file: File) : InputSource()
}

/**
 * Extrae y decodifica la primera pista de audio con MediaExtractor + MediaCodec.
 * Entrega el PCM tal cual lo da el decoder (S16 o F32, N canales, X Hz).
 */
internal class AudioDecoder(
  private val context: Context,
  private val input: InputSource,
) : AutoCloseable {

  interface Sink {
    /** Formato de salida real del decoder (no el de la pista). */
    fun onFormat(sampleRate: Int, channels: Int, pcmEncoding: Int)

    /** `buffer` es el ByteBuffer directo de MediaCodec; solo es válido durante la llamada. */
    fun onPcm(buffer: ByteBuffer, offset: Int, size: Int, presentationTimeUs: Long)
  }

  private val extractor = MediaExtractor()
  private var codec: MediaCodec? = null
  private var codecStarted = false
  private lateinit var trackFormat: MediaFormat

  /** Duración de la pista en µs; 0 si el contenedor no la indica. */
  var durationUs: Long = 0
    private set

  /** Abre la entrada y selecciona la primera pista de audio (paso 4). */
  fun open() {
    try {
      when (input) {
        is InputSource.Content -> extractor.setDataSource(context, input.uri, null)
        is InputSource.Path -> extractor.setDataSource(input.file.absolutePath)
      }
    } catch (e: SecurityException) {
      fail(ErrorCode.PERMISSION_DENIED, "Sin permiso para leer la entrada", e)
    } catch (e: FileNotFoundException) {
      fail(ErrorCode.FILE_NOT_FOUND, "No existe la entrada", e)
    } catch (e: IOException) {
      fail(ErrorCode.UNSUPPORTED_FORMAT, "El sistema no puede abrir el archivo", e)
    } catch (e: IllegalArgumentException) {
      fail(ErrorCode.UNSUPPORTED_FORMAT, "El sistema no puede abrir el archivo", e)
    }

    if (extractor.drmInitData != null) {
      fail(ErrorCode.DRM_PROTECTED, "El archivo está protegido con DRM")
    }

    val track = (0 until extractor.trackCount).firstOrNull { index ->
      extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
    } ?: fail(ErrorCode.NO_AUDIO_TRACK, "El archivo no tiene pista de audio")

    extractor.selectTrack(track)
    trackFormat = extractor.getTrackFormat(track)
    durationUs = if (trackFormat.containsKey(MediaFormat.KEY_DURATION)) {
      trackFormat.getLong(MediaFormat.KEY_DURATION).coerceAtLeast(0)
    } else {
      0
    }
  }

  /** Crea y arranca el decoder para la pista seleccionada. */
  fun startCodec() {
    val mime = trackFormat.getString(MediaFormat.KEY_MIME)
      ?: fail(ErrorCode.UNSUPPORTED_FORMAT, "Pista de audio sin MIME")
    val created = try {
      MediaCodec.createDecoderByType(mime)
    } catch (e: IOException) {
      fail(ErrorCode.UNSUPPORTED_FORMAT, "No hay decoder para $mime", e)
    } catch (e: IllegalArgumentException) {
      fail(ErrorCode.UNSUPPORTED_FORMAT, "No hay decoder para $mime", e)
    }
    codec = created
    try {
      created.configure(trackFormat, null, null, 0)
      created.start()
      codecStarted = true
    } catch (e: Exception) {
      fail(ErrorCode.UNSUPPORTED_FORMAT, "El decoder de $mime no acepta la pista", e)
    }
  }

  /** Bucle síncrono de input/output buffers hasta el final de la pista. */
  fun decode(sink: Sink, checkCancelled: () -> Unit) {
    val codec = codec ?: fail(ErrorCode.DECODER_ERROR, "Decoder no iniciado")
    val info = MediaCodec.BufferInfo()
    var inputDone = false
    var formatKnown = false

    fun publishFormat(format: MediaFormat) {
      val encoding = if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
        format.getInteger(MediaFormat.KEY_PCM_ENCODING)
      } else {
        AudioFormat.ENCODING_PCM_16BIT
      }
      sink.onFormat(
        format.getInteger(MediaFormat.KEY_SAMPLE_RATE),
        format.getInteger(MediaFormat.KEY_CHANNEL_COUNT),
        encoding,
      )
      formatKnown = true
    }

    try {
      while (true) {
        checkCancelled()

        if (!inputDone) {
          val inIndex = codec.dequeueInputBuffer(TIMEOUT_US)
          if (inIndex >= 0) {
            val buffer = codec.getInputBuffer(inIndex)
              ?: fail(ErrorCode.DECODER_ERROR, "Buffer de entrada nulo")
            val size = extractor.readSampleData(buffer, 0)
            if (size < 0) {
              codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
              inputDone = true
            } else {
              codec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
              extractor.advance()
            }
          }
        }

        val outIndex = codec.dequeueOutputBuffer(info, TIMEOUT_US)
        when {
          outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> publishFormat(codec.outputFormat)
          outIndex >= 0 -> {
            if (!formatKnown) {
              publishFormat(codec.getOutputFormat(outIndex))
            }
            if (info.size > 0) {
              val buffer = codec.getOutputBuffer(outIndex)
                ?: fail(ErrorCode.DECODER_ERROR, "Buffer de salida nulo")
              sink.onPcm(buffer, info.offset, info.size, info.presentationTimeUs)
            }
            codec.releaseOutputBuffer(outIndex, false)
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
              return
            }
          }
        }
      }
    } catch (e: Audio2Mp3Exception) {
      throw e
    } catch (e: MediaCodec.CodecException) {
      fail(ErrorCode.DECODER_ERROR, "Error del decoder: ${e.diagnosticInfo}", e)
    } catch (e: IllegalStateException) {
      fail(ErrorCode.DECODER_ERROR, "Error del decoder", e)
    }
  }

  override fun close() {
    codec?.let {
      if (codecStarted) {
        runCatching { it.stop() }
      }
      runCatching { it.release() }
    }
    codec = null
    runCatching { extractor.release() }
  }

  private companion object {
    const val TIMEOUT_US = 10_000L
  }
}
