package expo.modules.audio2mp3

import android.os.Debug
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Matriz de fixtures de integración (spec §10). La lanza scripts/run-fixtures-android.sh,
 * que sube fixtures/out/ a getExternalFilesDir("fixtures") y valida los MP3 con ffprobe.
 * Sin fixtures en el dispositivo el test se omite.
 */
@RunWith(AndroidJUnit4::class)
class FixturesTest {

  @Test
  fun convertsFixtureMatrix() {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val dir = context.getExternalFilesDir("fixtures")
    val expected = File(dir, "expected.tsv")
    assumeTrue("Sin fixtures en $dir", expected.exists())

    val results = File(dir, "results").apply {
      deleteRecursively()
      mkdirs()
    }
    val report = StringBuilder()
    val failures = mutableListOf<String>()

    expected.readLines().filter { it.isNotBlank() && !it.startsWith("#") }.forEach { line ->
      val cols = line.split('\t')
      val name = cols[0]
      val expect = cols[1]
      val rate = cols.getOrNull(2) ?: "-"
      val channels = cols.getOrNull(3) ?: "-"
      val input = File(dir, name)
      if (!input.exists() && expect == "OK") return@forEach // fixture opcional no generado

      val output = File(results, name.substringBeforeLast('.') + ".mp3")
      val heapBefore = Debug.getNativeHeapAllocatedSize()
      val start = System.nanoTime()
      try {
        val r = ConversionJob(context, ConvertParams(input.path, output.path, 192, true), CancellationToken()) {}.run()
        val elapsedMs = (System.nanoTime() - start) / 1_000_000
        val heapDeltaKb = (Debug.getNativeHeapAllocatedSize() - heapBefore) / 1024
        report.append("$name\tOK\t${r.sampleRate}\t${r.channels}\t${r.bitrate}\t${r.durationMs}\t${elapsedMs}ms\t${heapDeltaKb}KB\n")
        when {
          expect != "OK" -> failures += "$name: se esperaba $expect y convirtió"
          rate != "-" && rate.toInt() != r.sampleRate -> failures += "$name: ${r.sampleRate} Hz ≠ $rate"
          channels != "-" && channels.toInt() != r.channels -> failures += "$name: ${r.channels} canales ≠ $channels"
        }
      } catch (e: Audio2Mp3Exception) {
        report.append("$name\t${e.code}\t-\t-\t-\t-\n")
        if (e.code.name !in expect.split('|')) failures += "$name: ${e.code} (esperado $expect) ${e.message}"
        assertTrue("$name dejó .part", !File(output.path + ".part").exists())
      }
    }

    File(results, "results.tsv").writeText(report.toString())
    assertTrue(failures.joinToString("\n"), failures.isEmpty())
  }
}
