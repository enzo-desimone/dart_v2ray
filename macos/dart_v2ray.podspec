Pod::Spec.new do |s|
  s.name             = 'dart_v2ray'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin to run Xray/V2Ray as local proxy or VPN.'
  s.description      = 'Flutter plugin for Xray/V2Ray on macOS.'
  s.homepage         = 'https://github.com/enzo-desimone/dart_v2ray'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Enzo De Simone' => 'enzo.desimone1996@gmail.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*'
  s.dependency       'FlutterMacOS'
  s.platform         = :osx, '11.0'
  s.swift_version    = '5.0'

  s.prepare_command = <<-CMD
    set -euo pipefail

    FRAMEWORK_DIR="LibXray.xcframework"
    REQUIRED_BINARY="$FRAMEWORK_DIR/macos-arm64_x86_64/LibXray.framework/LibXray"
    FRAMEWORK_ZIP="LibXray.xcframework.zip"

    if [ -f "$REQUIRED_BINARY" ]; then
      echo "dart_v2ray: LibXray already present, skipping download."
      exit 0
    fi

    FRAMEWORK_URL="${DART_V2RAY_MACOS_FRAMEWORK_URL:-https://besimsoft.com/LibXray.xcframework.zip}"
    FRAMEWORK_ZIP_PATH="${DART_V2RAY_MACOS_FRAMEWORK_ZIP_PATH:-}"

    rm -rf "$FRAMEWORK_DIR" "$FRAMEWORK_ZIP"

    if [ -n "$FRAMEWORK_ZIP_PATH" ]; then
      echo "dart_v2ray: using local framework zip -> $FRAMEWORK_ZIP_PATH"

      if [ ! -f "$FRAMEWORK_ZIP_PATH" ]; then
        echo "dart_v2ray: zip not found at $FRAMEWORK_ZIP_PATH" >&2
        exit 1
      fi

      cp "$FRAMEWORK_ZIP_PATH" "$FRAMEWORK_ZIP"
    else
      echo "dart_v2ray: downloading LibXray from $FRAMEWORK_URL"
      curl -fL -o "$FRAMEWORK_ZIP" "$FRAMEWORK_URL"
    fi

    echo "dart_v2ray: extracting framework..."
    unzip -q "$FRAMEWORK_ZIP"
    rm "$FRAMEWORK_ZIP"

    if [ ! -f "$REQUIRED_BINARY" ]; then
      echo "dart_v2ray: invalid LibXray.xcframework structure" >&2
      exit 1
    fi

    echo "dart_v2ray: LibXray ready."
  CMD

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }

  s.xcconfig = {
    'OTHER_LDFLAGS' => '-framework LibXray'
  }

  s.libraries = 'resolv'
  s.vendored_frameworks = 'LibXray.xcframework'
end