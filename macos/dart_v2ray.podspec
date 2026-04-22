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

  s.prepare_command  = <<-CMD
    set -e
    BRIDGE_LIB="$(pwd)/xray_bridge_go/build/universal/libxraybridge.a"
    BRIDGE_HEADER="$(pwd)/xray_bridge_go/build/universal/libxraybridge.h"
    if [ ! -f "$BRIDGE_LIB" ] || [ ! -f "$BRIDGE_HEADER" ]; then
      echo "error: missing Go bridge artifacts. Run macos/xray_bridge_go/scripts/build_macos_bridge.sh first." >&2
      exit 1
    fi
  CMD

  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.resource_bundles = {
    'dart_v2ray_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
  s.resources = ['bin/geoip.dat', 'bin/geosite.dat']
  s.vendored_libraries = 'xray_bridge_go/build/universal/libxraybridge.a'
  s.static_framework = true
  s.libraries = 'c++'
  s.frameworks = 'NetworkExtension'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_LDFLAGS' => '$(inherited) -lc++',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/xray_bridge_go/build/universal" "${PODS_TARGET_SRCROOT}/xray_bridge_go/include"'
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -lc++'
  }
end
