Pod::Spec.new do |s|
  s.name             = 'dart_v2ray'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin to run Xray/V2Ray as local proxy.'
  s.description      = 'Flutter plugin for Xray/V2Ray on macOS.'
  s.homepage         = 'https://github.com/enzo-desimone/dart_v2ray'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Enzo De Simone' => 'en.desimone@outlook.it' }
  s.source           = { :path => '.' }

  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '11.5'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }

  s.frameworks = 'CoreFoundation', 'Security'
  s.libraries = 'resolv'
  s.vendored_frameworks = 'XRay.xcframework'
  s.swift_version = '5.0'
end