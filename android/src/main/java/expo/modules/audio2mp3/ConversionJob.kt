package expo.modules.audio2mp3

import android.content.Context
import android.media.AudioFormat
import android.net.Uri
import android.os.SystemClock
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.util.concurrent.atomic.AtomicBoolean

internal val BITRATES = setOf(64, 96, 128, 160, 192, 224, 256, 320)

internal data class ConvertParams(
  val input: String,
  val output: String,
  val bitrate: Int,
  val overwrite: Boolean,
)

internal data class ConvertOutcome(
  val uri: String,
  val durationMs: Long,
  val sizeBytes: Long,
  val sampleRate: Int,
  val channels: Int,
  val bitrate: Int,
) {
  fun toMap(): Map<String, Any> = mapOf(
    "uri" to uri,
    "durationMs" to durationMs.toDouble(),
    "sizeBytes" to sizeBytes.toDouble(),
    "sampleRate" to sampleRate,
    "channels" to channels,
    "bitrate" to bitrate,
  )
}

internal class CancellationToken {
  private val flag = AtomicBoolean(false)
  val isCancelled: Boolean get() = flag.get()
  fun cancel() = flag.set(true)
}

/** Registro `jobId → flag atómico de cancelación`, consultado entre chunks. */
internal class JobRegistry {
  private val jobs = HashMap<String, CancellationToken>()
  /** Cancelaciones que llegan antes de que la conversión se registre. */
  private val cancelledEarly = HashSet<String>()

  @Synchronized
  fun register(jobId: String): CancellationToken {
    val token = CancellationToken()
    if (cancelledEarly.remove(jobId)) {
      token.cancel()
    }
    jobs[jobId] = token
    return token
  }

  @Synchronized
  fun cancel(jobId: String) {
    val token = jobs[jobId]
    if (token != null) {
      token.cancel()
    } else {
      cancelledEarly.add(jobId)
    }
  }

  @Synchronized
  fun unregister(jobId: String) {
    jobs.remove(jobId)
  }

  @Synchronized
  fun cancelAll() {
    jobs.values.forEach { it.cancel() }
  }
}

/**
 * Una conversión completa (flujo común de la spec, §5). Se ejecuta en el hilo serie del módulo.
 * Ante cualquier error o cancelación libera decoder y encoder y borra `<output>.part`.
 */
internal class ConversionJob(
  private val context: Context,
  private val params: ConvertParams,
  private val token: CancellationToken,
  private val onProgress: (Double) -> Unit,
) {

  fun run(): ConvertOutcome {
    // 1. Opciones (JS ya las valida; se repite por si llaman al nativo directamente).
    if (params.bitrate !in BITRATES) {
      fail(ErrorCode.INVALID_BITRATE, "Bitrate no válido: ${params.bitrate}")
    }
    // 2-3. Entrada y salida.
    val input = resolveInput()
    val output = resolveOutput()
    checkOutput(output, input)
    checkCancelled()

    val part = File(output.path + PART_SUFFIX)
    try {
      AudioDecoder(context, input).use { decoder ->
        // 4. Primera pista de audio.
        decoder.open()
        checkSpace(output, decoder.durationUs)
        decoder.startCodec()
        // 5-8. Decodificar → convertir → codificar → escribir.
        val stats = Mp3Writer(part, params.bitrate, decoder.durationUs).use { writer ->
          decoder.decode(writer) { checkCancelled() }
          checkCancelled()
          writer.finish()
        }
        checkCancelled()
        // 9. Renombrar.
        if (output.exists() && !params.overwrite) {
          fail(ErrorCode.OUTPUT_EXISTS, "Ya existe ${output.path}")
        }
        if (!part.renameTo(output)) {
          fail(ErrorCode.OUTPUT_ERROR, "No se pudo renombrar ${part.name} a ${output.name}")
        }
        onProgress(1.0)
        // 10. Resultado.
        return ConvertOutcome(
          uri = Uri.fromFile(output).toString(),
          durationMs = stats.samplesPerChannel * 1000 / stats.sampleRate,
          sizeBytes = output.length(),
          sampleRate = stats.sampleRate,
          channels = stats.channels,
          bitrate = params.bitrate,
        )
      }
    } catch (t: Throwable) {
      part.delete()
      throw t
    }
  }

  private fun checkCancelled() {
    if (token.isCancelled) {
      fail(ErrorCode.CANCELLED, "Conversión cancelada")
    }
  }

  private fun resolveInput(): InputSource {
    val raw = params.input
    if (raw.startsWith("content://")) {
      val uri = Uri.parse(raw)
      try {
        val descriptor = context.contentResolver.openFileDescriptor(uri, "r")
          ?: fail(ErrorCode.FILE_NOT_FOUND, "No existe la entrada: $raw")
        descriptor.close()
      } catch (e: SecurityException) {
        fail(ErrorCode.PERMISSION_DENIED, "Sin permiso para leer $raw", e)
      } catch (e: FileNotFoundException) {
        fail(ErrorCode.FILE_NOT_FOUND, "No existe la entrada: $raw", e)
      } catch (e: IllegalArgumentException) {
        fail(ErrorCode.INVALID_PATH, "URI no válida: $raw", e)
      }
      return InputSource.Content(uri)
    }
    val file = toFile(raw) ?: fail(ErrorCode.INVALID_PATH, "Entrada no válida: $raw")
    when {
      !file.exists() -> fail(ErrorCode.FILE_NOT_FOUND, "No existe la entrada: ${file.path}")
      file.isDirectory -> fail(ErrorCode.INVALID_PATH, "La entrada es un directorio: ${file.path}")
      !file.canRead() -> fail(ErrorCode.PERMISSION_DENIED, "Sin permiso para leer ${file.path}")
    }
    return InputSource.Path(file)
  }

  private fun resolveOutput(): File =
    toFile(params.output) ?: fail(ErrorCode.INVALID_PATH, "Salida no válida: ${params.output}")

  private fun checkOutput(output: File, input: InputSource) {
    if (output.isDirectory) {
      fail(ErrorCode.INVALID_PATH, "La salida es un directorio: ${output.path}")
    }
    if (input is InputSource.Path && input.file.canonicalPath == output.canonicalPath) {
      fail(ErrorCode.INVALID_PATH, "La entrada y la salida son el mismo archivo")
    }
    val parent = output.absoluteFile.parentFile
      ?: fail(ErrorCode.INVALID_PATH, "Salida sin directorio: ${output.path}")
    if (!parent.isDirectory) {
      fail(ErrorCode.OUTPUT_ERROR, "No existe el directorio ${parent.path}")
    }
    if (!parent.canWrite()) {
      fail(ErrorCode.OUTPUT_ERROR, "No se puede escribir en ${parent.path}")
    }
    if (output.exists() && !params.overwrite) {
      fail(ErrorCode.OUTPUT_EXISTS, "Ya existe ${output.path}")
    }
  }

  /** Espacio libre ≥ duración × bitrate / 8 × 1.1. Sin duración conocida no se comprueba. */
  private fun checkSpace(output: File, durationUs: Long) {
    if (durationUs <= 0) return
    val estimate = durationUs / 1_000_000.0 * params.bitrate * 1000 / 8 * 1.1
    val free = output.absoluteFile.parentFile?.usableSpace ?: return
    if (free < estimate) {
      fail(ErrorCode.INSUFFICIENT_SPACE, "Espacio insuficiente: hacen falta ~${estimate.toLong()} bytes")
    }
  }

  private fun toFile(path: String): File? = when {
    path.startsWith("file://") -> Uri.parse(path).path?.let(::File)
    path.startsWith("/") -> File(path)
    else -> null
  }

  private class Stats(val sampleRate: Int, val channels: Int, val samplesPerChannel: Long)

  /**
   * Sink del decoder: PcmConverter → Mp3Encoder → `<output>.part`.
   * Buffers directos de tamaño fijo, reservados una vez (solo crecen si un bloque del
   * decoder es mayor que el anterior), así que la memoria no depende de la duración.
   */
  private inner class Mp3Writer(
    part: File,
    private val bitrate: Int,
    private val durationUs: Long,
  ) : AudioDecoder.Sink, AutoCloseable {

    private val stream: FileOutputStream = try {
      FileOutputStream(part)
    } catch (e: FileNotFoundException) {
      fail(ErrorCode.OUTPUT_ERROR, "No se pudo crear ${part.path}", e)
    }
    private val channel: FileChannel = stream.channel

    private var converter = 0L
    private var encoder = 0L
    private var inRate = 0
    private var inChannels = 0
    private var inFormat = -1
    private var outRate = 0
    private var outChannels = 0
    private var samplesPerChannel = 0L

    private var pcm: ByteBuffer = direct(PCM_BUFFER_BYTES)
    private var mp3: ByteBuffer = direct(PCM_BUFFER_BYTES)

    private var lastProgress = 0.0
    private var lastProgressAt = 0L

    override fun onFormat(sampleRate: Int, channels: Int, pcmEncoding: Int) {
      val format = when (pcmEncoding) {
        AudioFormat.ENCODING_PCM_16BIT -> NativeEncoder.FORMAT_S16
        AudioFormat.ENCODING_PCM_FLOAT -> NativeEncoder.FORMAT_F32
        else -> fail(ErrorCode.UNSUPPORTED_FORMAT, "Formato PCM del decoder no soportado: $pcmEncoding")
      }
      if (converter != 0L) {
        if (sampleRate == inRate && channels == inChannels && format == inFormat) return
        fail(ErrorCode.UNSUPPORTED_FORMAT, "El formato del audio cambia a mitad de la pista")
      }
      if (NativeEncoder.converterValidate(sampleRate, channels, format) != 0) {
        fail(ErrorCode.UNSUPPORTED_FORMAT, "PCM no soportado: $sampleRate Hz, $channels canales")
      }
      converter = NativeEncoder.converterCreate(sampleRate, channels, format)
      if (converter == 0L) fail(ErrorCode.ENCODER_ERROR, "No se pudo crear el converter")
      inRate = sampleRate
      inChannels = channels
      inFormat = format

      // 6. Encoder con la tasa y canales reales de salida del converter.
      outRate = NativeEncoder.converterOutRate(converter)
      outChannels = NativeEncoder.converterOutChannels(converter)
      encoder = NativeEncoder.create(outRate, outChannels, bitrate)
      if (encoder == 0L) {
        val code = NativeEncoder.validate(outRate, outChannels, bitrate)
        fail(
          if (code == ERR_INVALID_BITRATE) ErrorCode.INVALID_BITRATE else ErrorCode.ENCODER_ERROR,
          "No se pudo crear el encoder ($outRate Hz, $outChannels canales, $bitrate kbps): $code",
        )
      }
      // Frame Info (Xing + LAME): duración exacta y gapless; se reescribe al final.
      check(NativeEncoder.enableInfoFrame(encoder), "enableInfoFrame")
    }

    override fun onPcm(buffer: ByteBuffer, offset: Int, size: Int, presentationTimeUs: Long) {
      if (converter == 0L) fail(ErrorCode.DECODER_ERROR, "El decoder entregó audio sin formato")
      pcm = ensure(pcm, NativeEncoder.converterMaxOutputSamples(converter, size) * 2)
      val samples = result(NativeEncoder.converterProcess(converter, buffer, offset, size, pcm), "converterProcess")
      encode(samples)
      reportProgress(presentationTimeUs)
    }

    /** 8. Vacía converter y encoder, escribe el frame Info definitivo y cierra. */
    fun finish(): Stats {
      if (converter == 0L || encoder == 0L) {
        fail(ErrorCode.DECODER_ERROR, "El decoder no entregó audio")
      }
      pcm = ensure(pcm, NativeEncoder.converterMaxFlushSamples(converter) * 2)
      encode(result(NativeEncoder.converterFlush(converter, pcm), "converterFlush"))

      mp3 = ensure(mp3, NativeEncoder.maxFlushSize(encoder))
      write(result(NativeEncoder.flush(encoder, mp3), "flush"))

      val infoSize = NativeEncoder.infoFrameSize(encoder)
      if (infoSize > 0) {
        mp3 = ensure(mp3, infoSize)
        val written = result(NativeEncoder.infoFrame(encoder, mp3), "infoFrame")
        writeAt(written, 0)
      }
      try {
        channel.force(false)
        stream.close()
      } catch (e: IOException) {
        throw e.toOutputException()
      }
      return Stats(outRate, outChannels, samplesPerChannel)
    }

    private fun encode(samples: Int) {
      if (samples == 0) return
      mp3 = ensure(mp3, NativeEncoder.maxOutputSize(encoder, samples))
      write(result(NativeEncoder.encode(encoder, pcm, samples, mp3), "encode"))
      samplesPerChannel += samples / outChannels
    }

    private fun write(length: Int) {
      if (length == 0) return
      mp3.clear()
      mp3.limit(length)
      try {
        while (mp3.hasRemaining()) channel.write(mp3)
      } catch (e: IOException) {
        throw e.toOutputException()
      }
    }

    private fun writeAt(length: Int, position: Long) {
      mp3.clear()
      mp3.limit(length)
      try {
        var at = position
        while (mp3.hasRemaining()) at += channel.write(mp3, at)
      } catch (e: IOException) {
        throw e.toOutputException()
      }
    }

    /** Progreso = posición PCM / duración; como mucho cada 100 ms y cada 1 %. */
    private fun reportProgress(presentationTimeUs: Long) {
      if (durationUs <= 0) return
      val progress = (presentationTimeUs.toDouble() / durationUs).coerceIn(0.0, 1.0)
      val now = SystemClock.elapsedRealtime()
      if (progress - lastProgress >= 0.01 && now - lastProgressAt >= 100) {
        lastProgress = progress
        lastProgressAt = now
        onProgress(progress)
      }
    }

    override fun close() {
      if (encoder != 0L) NativeEncoder.destroy(encoder)
      if (converter != 0L) NativeEncoder.converterDestroy(converter)
      encoder = 0L
      converter = 0L
      runCatching { stream.close() }
    }

    private fun check(code: Int, what: String) {
      if (code != 0) fail(ErrorCode.ENCODER_ERROR, "$what falló: $code")
    }

    private fun result(value: Int, what: String): Int {
      if (value < 0) fail(ErrorCode.ENCODER_ERROR, "$what falló: ${-value}")
      return value
    }
  }

  private companion object {
    const val PART_SUFFIX = ".part"
    /** PCM ≈ 64 KB por bloque. */
    const val PCM_BUFFER_BYTES = 64 * 1024
    const val ERR_INVALID_BITRATE = 3

    fun direct(bytes: Int): ByteBuffer = ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder())

    fun ensure(buffer: ByteBuffer, bytes: Int): ByteBuffer =
      if (buffer.capacity() >= bytes) buffer else direct(bytes)
  }
}
