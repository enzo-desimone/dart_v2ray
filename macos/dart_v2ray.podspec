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

    if [ -f "$XRAY_BIN" ] && [ -f "$GEOIP_FILE" ] && [ -f "$GEOSITE_FILE" ]; then
      chmod +x "$XRAY_BIN" || true
      exit 0
    fi

    XRAY_VERSION="${DART_V2RAY_XRAY_VERSION:-v26.3.27}"
    DEFAULT_ARM64_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-macos-arm64-v8a.zip"
    DEFAULT_AMD64_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-macos-64.zip"

    ARM64_URL="${DART_V2RAY_MACOS_XRAY_ARM64_URL:-$DEFAULT_ARM64_URL}"
    AMD64_URL="${DART_V2RAY_MACOS_XRAY_AMD64_URL:-$DEFAULT_AMD64_URL}"
    ARM64_ZIP_SOURCE="${DART_V2RAY_MACOS_XRAY_ARM64_ZIP_PATH:-}"
    AMD64_ZIP_SOURCE="${DART_V2RAY_MACOS_XRAY_AMD64_ZIP_PATH:-}"
    ARM64_SHA256="${DART_V2RAY_MACOS_XRAY_ARM64_SHA256:-}"
    AMD64_SHA256="${DART_V2RAY_MACOS_XRAY_AMD64_SHA256:-}"

    WORK_DIR=".dart_v2ray_macos_runtime_tmp"
    ARM64_ZIP="$WORK_DIR/Xray-macos-arm64-v8a.zip"
    AMD64_ZIP="$WORK_DIR/Xray-macos-64.zip"
    ARM64_DIR="$WORK_DIR/arm64"
    AMD64_DIR="$WORK_DIR/amd64"

    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR" "$ARM64_DIR" "$AMD64_DIR"

    fetch_zip() {
      SOURCE_PATH="$1"
      URL="$2"
      EXPECTED_SHA="$3"
      ZIP_PATH="$4"
      LABEL="$5"

      if [ -n "$SOURCE_PATH" ]; then
        if [ ! -f "$SOURCE_PATH" ]; then
          echo "dart_v2ray(macOS): $LABEL zip path not found: $SOURCE_PATH" >&2
          exit 1
        fi
        cp "$SOURCE_PATH" "$ZIP_PATH"
      else
        curl -fL --retry 3 --retry-delay 1 -o "$ZIP_PATH" "$URL"
        if [ -z "$EXPECTED_SHA" ]; then
          DGST_PATH="${ZIP_PATH}.dgst"
          if curl -fsSL -o "$DGST_PATH" "${URL}.dgst"; then
            PARSED_SHA="$(sed -n 's/^sha256:\\([0-9a-fA-F]\\{64\\}\\).*/\\1/p' "$DGST_PATH" | head -n 1)"
            if [ -n "$PARSED_SHA" ]; then
              EXPECTED_SHA="$PARSED_SHA"
            fi
          fi
        fi
      fi

      if [ -n "$EXPECTED_SHA" ]; then
        echo "$EXPECTED_SHA  $ZIP_PATH" | shasum -a 256 -c -
      fi
    }

    fetch_zip "$ARM64_ZIP_SOURCE" "$ARM64_URL" "$ARM64_SHA256" "$ARM64_ZIP" "arm64"
    fetch_zip "$AMD64_ZIP_SOURCE" "$AMD64_URL" "$AMD64_SHA256" "$AMD64_ZIP" "amd64"

    unzip -q "$ARM64_ZIP" -d "$ARM64_DIR"
    unzip -q "$AMD64_ZIP" -d "$AMD64_DIR"

    ARM64_XRAY="$ARM64_DIR/xray"
    AMD64_XRAY="$AMD64_DIR/xray"

    if [ -f "$ARM64_XRAY" ] && [ -f "$AMD64_XRAY" ] && command -v lipo >/dev/null 2>&1; then
      lipo -create -output "$XRAY_BIN" "$ARM64_XRAY" "$AMD64_XRAY"
    else
      ARCH="$(uname -m)"
      if [ "$ARCH" = "arm64" ] && [ -f "$ARM64_XRAY" ]; then
        cp "$ARM64_XRAY" "$XRAY_BIN"
      elif [ -f "$AMD64_XRAY" ]; then
        cp "$AMD64_XRAY" "$XRAY_BIN"
      elif [ -f "$ARM64_XRAY" ]; then
        cp "$ARM64_XRAY" "$XRAY_BIN"
      else
        echo "dart_v2ray(macOS): xray binary missing in downloaded archives." >&2
        exit 1
      fi
    fi

    copy_geodata() {
      FILE_NAME="$1"
      if [ -f "$ARM64_DIR/$FILE_NAME" ]; then
        cp "$ARM64_DIR/$FILE_NAME" "$BIN_DIR/$FILE_NAME"
        return
      fi
      if [ -f "$AMD64_DIR/$FILE_NAME" ]; then
        cp "$AMD64_DIR/$FILE_NAME" "$BIN_DIR/$FILE_NAME"
        return
      fi
      echo "dart_v2ray(macOS): missing $FILE_NAME in downloaded archives." >&2
      exit 1
    }

    copy_geodata "geoip.dat"
    copy_geodata "geosite.dat"

    chmod +x "$XRAY_BIN"
    rm -rf "$WORK_DIR"
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
