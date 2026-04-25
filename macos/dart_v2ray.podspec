Pod::Spec.new do |s|
  s.name             = 'dart_v2ray'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin to run Xray/V2Ray as local proxy or VPN.'
  s.description      = <<-DESC
A Flutter macOS plugin bridge for Xray core with Packet Tunnel integration,
auto-disconnect support, and status streaming.
  DESC
  s.homepage         = 'https://github.com/enzo-desimone/dart_v2ray'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Enzo De Simone' => 'en.desimone@outlook.it' }
  s.source           = { :path => '.' }

  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'

  s.prepare_command = <<-CMD
    set -e
    FRAMEWORK_DIR="LibXray.xcframework"
    FRAMEWORK_ZIP="LibXray.xcframework.zip"

    if [ -d "$FRAMEWORK_DIR" ]; then
      exit 0
    fi

    DEFAULT_FRAMEWORK_URL="https://besimsoft.com/macos/LibXray.xcframework.zip"
    FRAMEWORK_URL="${DART_V2RAY_MACOS_FRAMEWORK_URL:-$DEFAULT_FRAMEWORK_URL}"
    FRAMEWORK_SHA256="${DART_V2RAY_MACOS_FRAMEWORK_SHA256:-}"
    FRAMEWORK_ZIP_PATH="${DART_V2RAY_MACOS_FRAMEWORK_ZIP_PATH:-}"

    rm -rf "$FRAMEWORK_DIR" "$FRAMEWORK_ZIP"

    if [ -n "$FRAMEWORK_ZIP_PATH" ]; then
      if [ ! -f "$FRAMEWORK_ZIP_PATH" ]; then
        echo "dart_v2ray: DART_V2RAY_MACOS_FRAMEWORK_ZIP_PATH not found: $FRAMEWORK_ZIP_PATH" >&2
        exit 1
      fi
      cp "$FRAMEWORK_ZIP_PATH" "$FRAMEWORK_ZIP"
    else
      curl -fL -A "Mozilla/5.0" -o "$FRAMEWORK_ZIP" "$FRAMEWORK_URL"
    fi

    if [ -n "$FRAMEWORK_SHA256" ]; then
      echo "$FRAMEWORK_SHA256  $FRAMEWORK_ZIP" | shasum -a 256 -c -
    else
      echo "dart_v2ray: DART_V2RAY_MACOS_FRAMEWORK_SHA256 not set; checksum verification skipped." >&2
    fi

    unzip -q "$FRAMEWORK_ZIP"
    rm "$FRAMEWORK_ZIP"

    if [ ! -d "$FRAMEWORK_DIR" ]; then
      echo "dart_v2ray: extracted LibXray.xcframework is invalid or incomplete." >&2
      exit 1
    fi
  CMD

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.xcconfig = { 'OTHER_LDFLAGS' => '-framework LibXray' }
  s.libraries = 'resolv'
  s.vendored_frameworks = 'LibXray.xcframework'
  s.swift_version = '5.0'
end
