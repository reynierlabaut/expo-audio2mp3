import ExpoModulesCore

struct ConvertOptionsRecord: Record {
  @Field var input: String = ""
  @Field var output: String = ""
  @Field var bitrate: Int = 192
  @Field var overwrite: Bool = false
}

public class Audio2Mp3Module: Module {
  /// Cola serie: una conversión a la vez, nunca en el hilo principal ni en el de JS.
  private let queue = DispatchQueue(label: "expo.modules.audio2mp3", qos: .userInitiated)
  private let jobs = JobRegistry()

  public func definition() -> ModuleDefinition {
    Name("ExpoAudio2Mp3")

    Events("onProgress")

    AsyncFunction("startConversion") { (jobId: String, options: ConvertOptionsRecord, promise: Promise) in
      let params = ConvertParams(
        input: options.input, output: options.output, bitrate: options.bitrate,
        overwrite: options.overwrite)
      let token = self.jobs.register(jobId)
      self.queue.async { [weak self] in
        defer { self?.jobs.unregister(jobId) }
        do {
          let result = try ConversionJob(params: params, token: token) { progress in
            self?.sendEvent("onProgress", ["jobId": jobId, "progress": progress])
          }.run()
          promise.resolve(result)
        } catch let error as Audio2Mp3Exception {
          promise.reject(error.code.rawValue, error.message)
        } catch {
          promise.reject(ErrorCode.decoderError.rawValue, error.localizedDescription)
        }
      }
    }

    Function("cancelConversion") { (jobId: String) in
      self.jobs.cancel(jobId)
    }

    OnDestroy {
      self.jobs.cancelAll()
    }
  }
}
