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
    BIN_DIR="bin"
    XRAY_BIN="$BIN_DIR/xray"
    GEOIP_FILE="$BIN_DIR/geoip.dat"
    GEOSITE_FILE="$BIN_DIR/geosite.dat"

    mkdir -p "$BIN_DIR"

    copy_runtime_file() {
      FILE_NAME="$1"
      SOURCE_DIR="$2"
      SOURCE_FILE="$SOURCE_DIR/$FILE_NAME"
      if [ ! -f "$SOURCE_FILE" ]; then
        echo "dart_v2ray(macOS): missing runtime file in DART_V2RAY_MACOS_RUNTIME_DIR: $SOURCE_FILE" >&2
        exit 1
      fi
      cp "$SOURCE_FILE" "$BIN_DIR/$FILE_NAME"
    }

    if [ ! -f "$XRAY_BIN" ] || [ ! -f "$GEOIP_FILE" ] || [ ! -f "$GEOSITE_FILE" ]; then
      if [ -n "${DART_V2RAY_MACOS_RUNTIME_DIR:-}" ]; then
        copy_runtime_file "xray" "$DART_V2RAY_MACOS_RUNTIME_DIR"
        copy_runtime_file "geoip.dat" "$DART_V2RAY_MACOS_RUNTIME_DIR"
        copy_runtime_file "geosite.dat" "$DART_V2RAY_MACOS_RUNTIME_DIR"
      else
        cat >&2 <<'MSG'
dart_v2ray(macOS): missing runtime files.
Provide all of the following files manually before `pod install`:
  - macos/bin/xray
  - macos/bin/geoip.dat
  - macos/bin/geosite.dat

Alternative: set DART_V2RAY_MACOS_RUNTIME_DIR to a folder containing:
  xray, geoip.dat, geosite.dat
MSG
        exit 1
      fi
    fi

    chmod +x "$XRAY_BIN" || true
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
