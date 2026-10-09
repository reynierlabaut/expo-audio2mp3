package expo.modules.audio2mp3

import expo.modules.kotlin.Promise
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class ConvertOptionsRecord : Record {
  @Field
  val input: String = ""

  @Field
  val output: String = ""

  @Field
  val bitrate: Int = 192

  @Field
  val overwrite: Boolean = false
}

class Audio2Mp3Module : Module() {
  private val jobs = JobRegistry()

  /** Cola serie: una conversión a la vez, nunca en el hilo principal ni en el de JS. */
  private val executor: ExecutorService by lazy {
    Executors.newSingleThreadExecutor { runnable ->
      Thread(runnable, "expo-audio2mp3").apply { isDaemon = true }
    }
  }

  override fun definition() = ModuleDefinition {
    Name("ExpoAudio2Mp3")

    Events("onProgress")

    AsyncFunction("startConversion") { jobId: String, options: ConvertOptionsRecord, promise: Promise ->
      val context = appContext.reactContext ?: throw Exceptions.ReactContextLost()
      val params = ConvertParams(options.input, options.output, options.bitrate, options.overwrite)
      val token = jobs.register(jobId)
      executor.execute {
        try {
          val outcome = ConversionJob(context, params, token) { progress ->
            sendEvent("onProgress", mapOf("jobId" to jobId, "progress" to progress))
          }.run()
          promise.resolve(outcome.toMap())
        } catch (e: Audio2Mp3Exception) {
          promise.reject(e.code.name, e.message, e)
        } catch (t: Throwable) {
          promise.reject(ErrorCode.DECODER_ERROR.name, t.message ?: t.javaClass.name, t)
        } finally {
          jobs.unregister(jobId)
        }
      }
    }

    Function("cancelConversion") { jobId: String ->
      jobs.cancel(jobId)
    }

    OnDestroy {
      jobs.cancelAll()
      executor.shutdown()
    }
  }
}
