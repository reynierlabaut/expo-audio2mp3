require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'ExpoAudio2Mp3'
  s.version        = package['version']
  s.summary        = package['description']
  s.description    = package['description']
  s.license        = package['license']
  s.author         = package['author']
  s.homepage       = package['homepage']
  s.platforms      = {
    :ios => '15.1'
  }
  s.swift_version  = '5.9'
  s.source         = { git: 'https://github.com/reynierlabaut/expo-audio2mp3.git' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  # audio2mp3-core precompilado (staticlib + audio2mp3.h + module.modulemap).
  # Lo descarga scripts/fetch-core.sh; no se compila Rust al instalar.
  s.vendored_frameworks = 'Audio2Mp3Core.xcframework'
  s.frameworks = 'AVFoundation'

  # Swift/Objective-C compatibility
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  s.source_files = "*.{h,m,mm,swift}"

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/*.swift'
  end
end
