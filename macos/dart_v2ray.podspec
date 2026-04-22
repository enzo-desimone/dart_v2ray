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

    PLUGIN_BIN_DIR="$(pwd)/bin"
    XRAY_BIN="$PLUGIN_BIN_DIR/xray"
    GEOIP_FILE="$PLUGIN_BIN_DIR/geoip.dat"
    GEOSITE_FILE="$PLUGIN_BIN_DIR/geosite.dat"

    missing=""
    [ -f "$XRAY_BIN" ]     || missing="${missing}\\n  - $XRAY_BIN"
    [ -f "$GEOIP_FILE" ]   || missing="${missing}\\n  - $GEOIP_FILE"
    [ -f "$GEOSITE_FILE" ] || missing="${missing}\\n  - $GEOSITE_FILE"

    if [ -n "$missing" ]; then
      printf 'dart_v2ray(macOS): runtime files missing from the plugin. Commit these files into macos/bin/ in the dart_v2ray package:\\n%b\\n' "$missing" >&2
      exit 1
    fi

    chmod +x "$XRAY_BIN"
  CMD

  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.resource_bundles = {
    'dart_v2ray_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
  s.resources = ['bin/xray', 'bin/geoip.dat', 'bin/geosite.dat']
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
