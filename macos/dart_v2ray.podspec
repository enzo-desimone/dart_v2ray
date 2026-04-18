Pod::Spec.new do |s|
  s.name             = 'dart_v2ray'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin to run Xray/V2Ray as local proxy or VPN.'
  s.description      = <<-DESC
A cross-platform Flutter plugin that manages VLESS/VMESS/Trojan/Shadowsocks
connections using Xray core. Includes macOS desktop bridge and
auto-disconnect support.
  DESC
  s.homepage         = 'https://github.com/enzo-desimone/dart_v2ray'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Enzo De Simone' => 'en.desimone@outlook.it' }
  s.source           = { :path => '.' }

  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.resource_bundles = {
    'dart_v2ray_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
  bundled_xray_files = Dir.glob('bin/xray*').select { |path| File.file?(path) }
  s.resources = bundled_xray_files unless bundled_xray_files.empty?
  s.static_framework = true
  s.libraries = 'c++'
  s.frameworks = 'NetworkExtension'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_LDFLAGS' => '$(inherited) -lc++'
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -lc++'
  }
end
