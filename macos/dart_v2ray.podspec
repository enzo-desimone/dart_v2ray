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

    PLUGIN_RUNTIME_DIR="$(pwd)/runtime"
    XRAY_BIN="$PLUGIN_RUNTIME_DIR/xray"
    GEOIP_FILE="$PLUGIN_RUNTIME_DIR/geoip.dat"
    GEOSITE_FILE="$PLUGIN_RUNTIME_DIR/geosite.dat"

    missing=""
    [ -f "$XRAY_BIN" ]     || missing="${missing}\\n  - $XRAY_BIN"
    [ -f "$GEOIP_FILE" ]   || missing="${missing}\\n  - $GEOIP_FILE"
    [ -f "$GEOSITE_FILE" ] || missing="${missing}\\n  - $GEOSITE_FILE"

    if [ -n "$missing" ]; then
      printf 'dart_v2ray(macOS): runtime files missing from the plugin. Commit these files into macos/runtime/ in the dart_v2ray package:\\n%b\\n' "$missing" >&2
      exit 1
    fi

    chmod +x "$XRAY_BIN"
  CMD

  s.script_phases = [
    {
      :name => 'dart_v2ray Embed macOS Runtime Helper',
      :execution_position => :after_compile,
      :shell_path => '/bin/sh',
      :script => <<-SCRIPT
        set -euo pipefail

        if [ "${PLATFORM_NAME:-}" != "macosx" ]; then
          exit 0
        fi

        PLUGIN_ROOT="${PODS_TARGET_SRCROOT}"
        RUNTIME_SRC_DIR="${PLUGIN_ROOT}/runtime"
        HELPER_SWIFT_SRC="${PLUGIN_ROOT}/runtime_helper/DartV2RayRuntimeHelper.swift"

        RUNTIME_DST_DIR="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Resources/dart_v2ray_runtime"
        HELPER_DST_DIR="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
        HELPER_DST_PATH="${HELPER_DST_DIR}/dart_v2ray_runtime_helper"

        for f in "${RUNTIME_SRC_DIR}/xray" "${RUNTIME_SRC_DIR}/geoip.dat" "${RUNTIME_SRC_DIR}/geosite.dat" "${HELPER_SWIFT_SRC}"; do
          if [ ! -f "$f" ]; then
            echo "error: dart_v2ray missing required runtime artifact: $f"
            exit 1
          fi
        done

        mkdir -p "${RUNTIME_DST_DIR}" "${HELPER_DST_DIR}"

        cp -f "${RUNTIME_SRC_DIR}/xray" "${RUNTIME_DST_DIR}/xray"
        cp -f "${RUNTIME_SRC_DIR}/geoip.dat" "${RUNTIME_DST_DIR}/geoip.dat"
        cp -f "${RUNTIME_SRC_DIR}/geosite.dat" "${RUNTIME_DST_DIR}/geosite.dat"
        chmod +x "${RUNTIME_DST_DIR}/xray"

        SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
        xcrun swiftc \
          -O \
          -sdk "${SDK_PATH}" \
          -target "${ARCHS%% *}-apple-macos10.14" \
          "${HELPER_SWIFT_SRC}" \
          -o "${HELPER_DST_PATH}"
        chmod +x "${HELPER_DST_PATH}"

        if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ]; then
          /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${RUNTIME_DST_DIR}/xray"
          /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${HELPER_DST_PATH}"
        fi
      SCRIPT
    }
  ]

  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.resource_bundles = {
    'dart_v2ray_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
  s.resources = ['runtime/geoip.dat', 'runtime/geosite.dat']
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
