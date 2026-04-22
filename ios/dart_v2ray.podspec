Pod::Spec.new do |s|
  s.name             = 'dart_v2ray'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin to run Xray/V2Ray as local proxy or VPN.'
  s.description      = <<-DESC
A cross-platform Flutter plugin that manages VLESS/VMESS/Trojan/Shadowsocks
connections using Xray core. Includes iOS Network Extension bridge and
auto-disconnect support.
  DESC
  s.homepage         = 'https://github.com/enzo-desimone/dart_v2ray'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Enzo De Simone' => 'en.desimone@outlook.it' }
  s.source           = { :path => '.' }

  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  s.prepare_command = <<-CMD
    set -e
    FRAMEWORK_DIR="XRay.xcframework"
    REQUIRED_BINARY="$FRAMEWORK_DIR/ios-arm64/XRay.framework/XRay"
    FRAMEWORK_ZIP="XRay.xcframework.zip"

    # If framework is already vendored in the plugin, nothing else is required.
    if [ -f "$REQUIRED_BINARY" ]; then
      exit 0
    fi

    # Default hosted framework source (override with env vars if needed).
    DEFAULT_FRAMEWORK_URL="https://github.com/shafiquecbl/flutter_v2ray_plus/releases/download/framework-v1.0.0/XRay.xcframework.zip"
    DEFAULT_FRAMEWORK_SHA256="ab14d797a3efe5cd148054e7bd1923d95b355cee9b0a36e5a81782c6fd517d1a"
    FRAMEWORK_URL="${DART_V2RAY_IOS_FRAMEWORK_URL:-$DEFAULT_FRAMEWORK_URL}"
    FRAMEWORK_SHA256="${DART_V2RAY_IOS_FRAMEWORK_SHA256:-$DEFAULT_FRAMEWORK_SHA256}"
    FRAMEWORK_ZIP_PATH="${DART_V2RAY_IOS_FRAMEWORK_ZIP_PATH:-}"

    rm -rf "$FRAMEWORK_DIR" "$FRAMEWORK_ZIP"

    if [ -n "$FRAMEWORK_ZIP_PATH" ]; then
      if [ ! -f "$FRAMEWORK_ZIP_PATH" ]; then
        echo "dart_v2ray: DART_V2RAY_IOS_FRAMEWORK_ZIP_PATH not found: $FRAMEWORK_ZIP_PATH" >&2
        exit 1
      fi
      cp "$FRAMEWORK_ZIP_PATH" "$FRAMEWORK_ZIP"
    else
      curl -fL -o "$FRAMEWORK_ZIP" "$FRAMEWORK_URL"
      echo "$FRAMEWORK_SHA256  $FRAMEWORK_ZIP" | shasum -a 256 -c -
    fi

    unzip -q "$FRAMEWORK_ZIP"
    rm "$FRAMEWORK_ZIP"

    if [ ! -f "$REQUIRED_BINARY" ]; then
      echo "dart_v2ray: extracted XRay.xcframework is invalid or incomplete." >&2
      exit 1
    fi
  CMD

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.xcconfig = { 'OTHER_LDFLAGS' => '-framework XRay' }
  s.libraries = 'resolv'
  s.vendored_frameworks = 'XRay.xcframework'
  s.swift_version = '5.0'
end
