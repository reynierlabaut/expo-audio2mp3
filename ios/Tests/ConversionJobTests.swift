import XCTest

@testable import ExpoAudio2Mp3

/// Ejecutar desde example/ios con el test_spec del podspec (Xcode → Product → Test).
final class ConversionJobTests: XCTestCase {
  private var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent("audio2mp3-test")
    try? FileManager.default.removeItem(at: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  func testWavStereo441ConvertsWithoutResampling() throws {
    let input = try wav("stereo.wav", sampleRate: 44_100, channels: 2, seconds: 2)
    let output = dir.appendingPathComponent("stereo.mp3")
    let result = try convert(input, output)

    XCTAssertEqual(result["sampleRate"] as? Int, 44_100)
    XCTAssertEqual(result["channels"] as? Int, 2)
    XCTAssertEqual(result["bitrate"] as? Int, 192)
    XCTAssertEqual(result["durationMs"] as? Double ?? 0, 2000, accuracy: 30)
    XCTAssertTrue((result["uri"] as? String ?? "").hasPrefix("file://"))
    try assertMp3(output)
    assertNoPart(output)
  }

  func testWav16kMonoIsResampledTo32k() throws {
    let input = try wav("mono16k.wav", sampleRate: 16_000, channels: 1, seconds: 1)
    let result = try convert(input, dir.appendingPathComponent("mono.mp3"), bitrate: 64)
    XCTAssertEqual(result["sampleRate"] as? Int, 32_000)
    XCTAssertEqual(result["channels"] as? Int, 1)
  }

  func testSurroundIsDownmixedToStereo() throws {
    let input = try wav("surround.wav", sampleRate: 48_000, channels: 6, seconds: 1)
    let result = try convert(input, dir.appendingPathComponent("surround.mp3"))
    XCTAssertEqual(result["channels"] as? Int, 2)
  }

  func testTargetRateRule() {
    XCTAssertEqual(AudioDecoder.targetRate(for: 44_100), 44_100)
    XCTAssertEqual(AudioDecoder.targetRate(for: 8_000), 32_000)
    XCTAssertEqual(AudioDecoder.targetRate(for: 22_050), 44_100)
    XCTAssertEqual(AudioDecoder.targetRate(for: 96_000), 48_000)
    XCTAssertEqual(AudioDecoder.targetRate(for: 37_800), 48_000)
  }

  func testExistingOutputFailsWithoutOverwrite() throws {
    let input = try wav("a.wav", sampleRate: 44_100, channels: 1, seconds: 0.5)
    let output = dir.appendingPathComponent("a.mp3")
    try "previo".write(to: output, atomically: true, encoding: .utf8)
    XCTAssertEqual(try errorCode { try self.convert(input, output) }, .outputExists)
    XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "previo")
    assertNoPart(output)
  }

  func testOverwriteReplacesExistingOutput() throws {
    let input = try wav("b.wav", sampleRate: 44_100, channels: 1, seconds: 0.5)
    let output = dir.appendingPathComponent("b.mp3")
    try "previo".write(to: output, atomically: true, encoding: .utf8)
    _ = try convert(input, output, overwrite: true)
    try assertMp3(output)
    assertNoPart(output)
  }

  func testMissingInputIsFileNotFound() throws {
    let code = try errorCode {
      try self.convert(self.dir.appendingPathComponent("no.mp4"), self.dir.appendingPathComponent("x.mp3"))
    }
    XCTAssertEqual(code, .fileNotFound)
  }

  func testCorruptInputFailsAndLeavesNoPart() throws {
    let input = dir.appendingPathComponent("texto.mp4")
    try String(repeating: "esto no es un vídeo ", count: 200).write(to: input, atomically: true, encoding: .utf8)
    let output = dir.appendingPathComponent("corrupto.mp3")
    let code = try errorCode { try self.convert(input, output) }
    XCTAssertTrue([.unsupportedFormat, .decoderError, .noAudioTrack].contains(code), "\(code)")
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    assertNoPart(output)
  }

  func testCancelledJobLeavesNoFiles() throws {
    let input = try wav("c.wav", sampleRate: 44_100, channels: 2, seconds: 2)
    let output = dir.appendingPathComponent("c.mp3")
    let token = CancellationToken()
    let job = ConversionJob(
      params: ConvertParams(input: input.path, output: output.path, bitrate: 128, overwrite: false),
      token: token
    ) { _ in token.cancel() }
    XCTAssertEqual(try errorCode { _ = try job.run() }, .cancelled)
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    assertNoPart(output)
  }

  func testCancelBeforeRegisterIsHonoured() {
    let registry = JobRegistry()
    registry.cancel("job-1")
    XCTAssertTrue(registry.register("job-1").isCancelled)
    XCTAssertFalse(registry.register("job-2").isCancelled)
  }

  func testRepeatedConversionsReleaseHandles() throws {
    let input = try wav("e.wav", sampleRate: 44_100, channels: 2, seconds: 0.5)
    for i in 0..<20 {
      _ = try convert(input, dir.appendingPathComponent("e\(i).mp3"))
    }
  }

  // MARK: - helpers

  private func convert(_ input: URL, _ output: URL, bitrate: Int = 192, overwrite: Bool = false) throws
    -> [String: Any]
  {
    try ConversionJob(
      params: ConvertParams(input: input.path, output: output.path, bitrate: bitrate, overwrite: overwrite),
      token: CancellationToken()
    ) { _ in }.run()
  }

  private func errorCode(_ block: () throws -> Void) throws -> ErrorCode {
    do {
      try block()
    } catch let error as Audio2Mp3Exception {
      return error.code
    }
    XCTFail("Se esperaba Audio2Mp3Exception")
    throw NSError(domain: "test", code: 0)
  }

  private func assertMp3(_ url: URL) throws {
    let header = try Data(contentsOf: url).prefix(2)
    XCTAssertEqual(header.first, 0xFF)
    XCTAssertEqual((header.last ?? 0) & 0xE0, 0xE0)
  }

  private func assertNoPart(_ output: URL) {
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.path + ".part"))
  }

  /// WAV PCM 16-bit con un seno de 440 Hz en cada canal.
  private func wav(_ name: String, sampleRate: Int, channels: Int, seconds: Double) throws -> URL {
    let frames = Int(Double(sampleRate) * seconds)
    let dataBytes = frames * channels * 2
    var data = Data()
    func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
    func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { data.append(contentsOf: $0) } }
    data.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes); data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(channels)
    u32(sampleRate); u32(sampleRate * channels * 2); u16(channels * 2); u16(16)
    data.append(contentsOf: Array("data".utf8)); u32(dataBytes)
    for i in 0..<frames {
      let sample = Int16(sin(2 * Double.pi * 440 * Double(i) / Double(sampleRate)) * 12_000)
      for _ in 0..<channels {
        withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
      }
    }
    let url = dir.appendingPathComponent(name)
    try data.write(to: url)
    return url
  }
}
