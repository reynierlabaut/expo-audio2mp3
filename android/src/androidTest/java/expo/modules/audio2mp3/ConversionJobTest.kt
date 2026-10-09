package expo.modules.audio2mp3

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Ejecutar desde una app con el módulo (p. ej. example/):
 *   cd example/android && ./gradlew :expo-audio2mp3:connectedAndroidTest
 */
@RunWith(AndroidJUnit4::class)
class ConversionJobTest {
  private lateinit var context: Context
  private lateinit var dir: File

  @Before
  fun setUp() {
    context = InstrumentationRegistry.getInstrumentation().targetContext
    dir = File(context.cacheDir, "audio2mp3-test").apply {
      deleteRecursively()
      mkdirs()
    }
  }

  @After
  fun tearDown() {
    dir.deleteRecursively()
  }

  @Test
  fun wavStereo441ConvertsWithoutResampling() {
    val input = wav("stereo.wav", sampleRate = 44_100, channels = 2, seconds = 2.0)
    val output = File(dir, "stereo.mp3")
    val result = convert(input, output)

    assertEquals(44_100, result.sampleRate)
    assertEquals(2, result.channels)
    assertEquals(192, result.bitrate)
    assertTrue("duración ${result.durationMs}", abs(result.durationMs - 2000) <= 30)
    assertEquals(output.length(), result.sizeBytes)
    assertTrue(result.uri.startsWith("file://"))
    assertMp3(output)
    assertNoPart(output)
  }

  @Test
  fun wav16kMonoIsResampledTo32k() {
    val input = wav("mono16k.wav", sampleRate = 16_000, channels = 1, seconds = 1.0)
    val result = convert(input, File(dir, "mono.mp3"), bitrate = 64)
    assertEquals(32_000, result.sampleRate)
    assertEquals(1, result.channels)
    assertTrue("duración ${result.durationMs}", abs(result.durationMs - 1000) <= 40)
  }

  @Test
  fun wavSurroundIsDownmixedToStereo() {
    val input = wav("surround.wav", sampleRate = 48_000, channels = 6, seconds = 1.0)
    val result = convert(input, File(dir, "surround.mp3"))
    assertEquals(48_000, result.sampleRate)
    assertEquals(2, result.channels)
  }

  @Test
  fun wav96kIsResampledTo48k() {
    val input = wav("hires.wav", sampleRate = 96_000, channels = 2, seconds = 1.0)
    val result = convert(input, File(dir, "hires.mp3"), bitrate = 320)
    assertEquals(48_000, result.sampleRate)
  }

  @Test
  fun existingOutputFailsWithoutOverwrite() {
    val input = wav("a.wav", 44_100, 1, 0.5)
    val output = File(dir, "a.mp3").apply { writeText("previo") }
    expectError(ErrorCode.OUTPUT_EXISTS) { convert(input, output) }
    assertEquals("previo", output.readText())
    assertNoPart(output)
  }

  @Test
  fun overwriteReplacesExistingOutput() {
    val input = wav("b.wav", 44_100, 1, 0.5)
    val output = File(dir, "b.mp3").apply { writeText("previo") }
    convert(input, output, overwrite = true)
    assertMp3(output)
    assertNoPart(output)
  }

  @Test
  fun missingInputIsFileNotFound() {
    expectError(ErrorCode.FILE_NOT_FOUND) {
      convert(File(dir, "no-existe.mp4"), File(dir, "x.mp3"))
    }
  }

  @Test
  fun corruptInputFailsAndLeavesNoPart() {
    val input = File(dir, "texto.mp4").apply { writeText("esto no es un vídeo ".repeat(200)) }
    val output = File(dir, "corrupto.mp3")
    val error = captureError { convert(input, output) }
    assertTrue(
      "código ${error.code}",
      error.code == ErrorCode.UNSUPPORTED_FORMAT || error.code == ErrorCode.DECODER_ERROR,
    )
    assertFalse(output.exists())
    assertNoPart(output)
  }

  @Test
  fun cancelledJobLeavesNoFiles() {
    val input = wav("c.wav", 44_100, 2, 2.0)
    val output = File(dir, "c.mp3")
    val token = CancellationToken()
    var cancelledAt = -1.0
    expectError(ErrorCode.CANCELLED) {
      ConversionJob(context, ConvertParams(input.path, output.path, 128, false), token) { progress ->
        if (cancelledAt < 0) {
          cancelledAt = progress
          token.cancel()
        }
      }.run()
    }
    assertFalse(output.exists())
    assertNoPart(output)
  }

  @Test
  fun cancelBeforeRegisterIsHonoured() {
    val registry = JobRegistry()
    registry.cancel("job-1")
    assertTrue(registry.register("job-1").isCancelled)
    assertFalse(registry.register("job-2").isCancelled)
  }

  @Test
  fun invalidBitrateIsRejected() {
    val input = wav("d.wav", 44_100, 1, 0.2)
    expectError(ErrorCode.INVALID_BITRATE) { convert(input, File(dir, "d.mp3"), bitrate = 100) }
  }

  @Test
  fun repeatedConversionsReleaseNativeHandles() {
    val input = wav("e.wav", 44_100, 2, 0.5)
    repeat(20) { i -> convert(input, File(dir, "e$i.mp3")) }
    assertEquals(20, dir.listFiles { f -> f.name.endsWith(".mp3") }!!.size)
  }

  // ------------------------------------------------------------------ helpers

  private fun convert(
    input: File,
    output: File,
    bitrate: Int = 192,
    overwrite: Boolean = false,
  ): ConvertOutcome =
    ConversionJob(context, ConvertParams(input.path, output.path, bitrate, overwrite), CancellationToken()) {}.run()

  private fun captureError(block: () -> Unit): Audio2Mp3Exception {
    try {
      block()
    } catch (e: Audio2Mp3Exception) {
      return e
    }
    fail("Se esperaba Audio2Mp3Exception")
    throw IllegalStateException()
  }

  private fun expectError(code: ErrorCode, block: () -> Unit) {
    assertEquals(code, captureError(block).code)
  }

  private fun assertMp3(file: File) {
    val header = ByteArray(4)
    RandomAccessFile(file, "r").use { it.readFully(header) }
    assertEquals(0xFF, header[0].toInt() and 0xFF)
    assertEquals(0xE0, header[1].toInt() and 0xE0)
  }

  private fun assertNoPart(output: File) {
    assertFalse("queda ${output.name}.part", File(output.path + ".part").exists())
  }

  /** WAV PCM 16-bit con un seno de 440 Hz en cada canal. */
  private fun wav(name: String, sampleRate: Int, channels: Int, seconds: Double): File {
    val frames = (sampleRate * seconds).toInt()
    val dataBytes = frames * channels * 2
    val buffer = ByteBuffer.allocate(44 + dataBytes).order(ByteOrder.LITTLE_ENDIAN)
    buffer.put("RIFF".toByteArray()).putInt(36 + dataBytes).put("WAVE".toByteArray())
    buffer.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(channels.toShort())
    buffer.putInt(sampleRate).putInt(sampleRate * channels * 2)
    buffer.putShort((channels * 2).toShort()).putShort(16)
    buffer.put("data".toByteArray()).putInt(dataBytes)
    for (i in 0 until frames) {
      val sample = (sin(2 * PI * 440 * i / sampleRate) * 12_000).toInt().toShort()
      repeat(channels) { buffer.putShort(sample) }
    }
    return File(dir, name).apply { writeBytes(buffer.array()) }
  }
}
