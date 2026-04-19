cmake_minimum_required(VERSION 3.14)
project(dart_v2ray_plugin LANGUAGES CXX)

add_library(dart_v2ray_plugin SHARED
  "dart_v2ray_plugin.cpp"
  "dart_v2ray_plugin_c_api.cpp"
  "../shared/desktop_v2ray_core.cc"
)

apply_standard_settings(dart_v2ray_plugin)

set_target_properties(dart_v2ray_plugin PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(dart_v2ray_plugin PRIVATE FLUTTER_PLUGIN_IMPL)
target_compile_features(dart_v2ray_plugin PRIVATE cxx_std_17)

target_include_directories(dart_v2ray_plugin PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(dart_v2ray_plugin PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../shared")

target_link_libraries(dart_v2ray_plugin PRIVATE
  flutter
  flutter_wrapper_plugin
  ws2_32
  iphlpapi)

set(DART_V2RAY_XRAY_VERSION "v26.3.27" CACHE STRING
  "Pinned Xray release tag used by dart_v2ray runtime auto-download.")
set(DART_V2RAY_WINDOWS_XRAY_ZIP_PATH "" CACHE FILEPATH
  "Local path to Xray-windows-64.zip. If set, download is skipped.")
set(DART_V2RAY_WINDOWS_XRAY_ZIP_URL "" CACHE STRING
  "Remote URL for Xray-windows-64.zip.")
set(DART_V2RAY_WINDOWS_XRAY_DGST_URL "" CACHE STRING
  "Remote URL for Xray-windows-64.zip.dgst checksum file.")
set(DART_V2RAY_WINDOWS_XRAY_ZIP_SHA256 "" CACHE STRING
  "Expected SHA256 for Xray-windows-64.zip. Overrides .dgst lookup when set.")

function(_dart_v2ray_select_existing out_var)
  foreach(_path ${ARGN})
    if(EXISTS "${_path}")
      set(${out_var} "${_path}" PARENT_SCOPE)
      return()
    endif()
  endforeach()
  set(${out_var} "" PARENT_SCOPE)
endfunction()

function(_dart_v2ray_read_setting out_var cache_var env_var default_value)
  set(_value "")
  if(NOT "${${cache_var}}" STREQUAL "")
    set(_value "${${cache_var}}")
  elseif(DEFINED ENV{${env_var}} AND NOT "$ENV{${env_var}}" STREQUAL "")
    set(_value "$ENV{${env_var}}")
  else()
    set(_value "${default_value}")
  endif()
  set(${out_var} "${_value}" PARENT_SCOPE)
endfunction()

function(_dart_v2ray_download_file url output_path label)
  file(DOWNLOAD "${url}" "${output_path}"
    STATUS _download_status
    LOG _download_log
    SHOW_PROGRESS
    TLS_VERIFY ON)
  list(GET _download_status 0 _download_code)
  if(NOT _download_code EQUAL 0)
    list(GET _download_status 1 _download_message)
    message(FATAL_ERROR
      "dart_v2ray: failed to download ${label} from ${url}. "
      "(${_download_code}) ${_download_message}")
  endif()
endfunction()

function(_dart_v2ray_verify_sha256 file_path expected_sha label)
  if("${expected_sha}" STREQUAL "")
    return()
  endif()

  if(NOT EXISTS "${file_path}")
    message(FATAL_ERROR "dart_v2ray: cannot verify ${label}, file not found: ${file_path}")
  endif()

  file(SHA256 "${file_path}" _actual_sha)
  string(TOLOWER "${_actual_sha}" _actual_sha_lower)
  string(TOLOWER "${expected_sha}" _expected_sha_lower)
  if(NOT _actual_sha_lower STREQUAL _expected_sha_lower)
    message(FATAL_ERROR
      "dart_v2ray: SHA256 mismatch for ${label}. "
      "expected=${_expected_sha_lower} actual=${_actual_sha_lower}")
  endif()
endfunction()

set(dart_v2ray_bundled_libraries "")

# Allow runtime binaries to live in the plugin package or in the consuming
# app's windows/ tree (legacy/manual behavior).
set(_dart_v2ray_xray_local_candidates
  "${CMAKE_CURRENT_SOURCE_DIR}/bin/xray.exe"
  "${CMAKE_SOURCE_DIR}/bin/xray.exe"
  "${CMAKE_SOURCE_DIR}/runner/bin/xray.exe")

set(_dart_v2ray_wintun_local_candidates
  "${CMAKE_CURRENT_SOURCE_DIR}/bin/wintun.dll"
  "${CMAKE_SOURCE_DIR}/bin/wintun.dll"
  "${CMAKE_SOURCE_DIR}/runner/bin/wintun.dll")

set(_dart_v2ray_geoip_local_candidates
  "${CMAKE_CURRENT_SOURCE_DIR}/bin/geoip.dat"
  "${CMAKE_SOURCE_DIR}/bin/geoip.dat"
  "${CMAKE_SOURCE_DIR}/runner/bin/geoip.dat")

set(_dart_v2ray_geosite_local_candidates
  "${CMAKE_CURRENT_SOURCE_DIR}/bin/geosite.dat"
  "${CMAKE_SOURCE_DIR}/bin/geosite.dat"
  "${CMAKE_SOURCE_DIR}/runner/bin/geosite.dat")

_dart_v2ray_select_existing(_dart_v2ray_xray_executable ${_dart_v2ray_xray_local_candidates})
_dart_v2ray_select_existing(_dart_v2ray_wintun_dll ${_dart_v2ray_wintun_local_candidates})
_dart_v2ray_select_existing(_dart_v2ray_geoip_dat ${_dart_v2ray_geoip_local_candidates})
_dart_v2ray_select_existing(_dart_v2ray_geosite_dat ${_dart_v2ray_geosite_local_candidates})

if(_dart_v2ray_xray_executable STREQUAL ""
   OR _dart_v2ray_wintun_dll STREQUAL ""
   OR _dart_v2ray_geoip_dat STREQUAL ""
   OR _dart_v2ray_geosite_dat STREQUAL "")
  set(_dart_v2ray_download_dir "${CMAKE_CURRENT_BINARY_DIR}/dart_v2ray_downloads")
  set(_dart_v2ray_runtime_dir "${CMAKE_CURRENT_BINARY_DIR}/dart_v2ray_runtime")
  file(MAKE_DIRECTORY "${_dart_v2ray_download_dir}")
  file(MAKE_DIRECTORY "${_dart_v2ray_runtime_dir}")

  set(_dart_v2ray_default_xray_zip_url
    "https://github.com/XTLS/Xray-core/releases/download/${DART_V2RAY_XRAY_VERSION}/Xray-windows-64.zip")
  set(_dart_v2ray_default_xray_dgst_url "${_dart_v2ray_default_xray_zip_url}.dgst")

  _dart_v2ray_read_setting(
    _dart_v2ray_xray_zip_path
    DART_V2RAY_WINDOWS_XRAY_ZIP_PATH
    DART_V2RAY_WINDOWS_XRAY_ZIP_PATH
    "")
  _dart_v2ray_read_setting(
    _dart_v2ray_xray_zip_url
    DART_V2RAY_WINDOWS_XRAY_ZIP_URL
    DART_V2RAY_WINDOWS_XRAY_ZIP_URL
    "${_dart_v2ray_default_xray_zip_url}")
  _dart_v2ray_read_setting(
    _dart_v2ray_xray_dgst_url
    DART_V2RAY_WINDOWS_XRAY_DGST_URL
    DART_V2RAY_WINDOWS_XRAY_DGST_URL
    "${_dart_v2ray_default_xray_dgst_url}")
  _dart_v2ray_read_setting(
    _dart_v2ray_xray_sha256
    DART_V2RAY_WINDOWS_XRAY_ZIP_SHA256
    DART_V2RAY_WINDOWS_XRAY_ZIP_SHA256
    "")

  if(_dart_v2ray_xray_zip_path STREQUAL "")
    set(_dart_v2ray_xray_zip_path "${_dart_v2ray_download_dir}/Xray-windows-64.zip")
    message(STATUS "dart_v2ray: downloading Windows runtime from ${_dart_v2ray_xray_zip_url}")
    _dart_v2ray_download_file(
      "${_dart_v2ray_xray_zip_url}"
      "${_dart_v2ray_xray_zip_path}"
      "Xray-windows-64.zip")
  elseif(NOT EXISTS "${_dart_v2ray_xray_zip_path}")
    message(FATAL_ERROR
      "dart_v2ray: DART_V2RAY_WINDOWS_XRAY_ZIP_PATH does not exist: "
      "${_dart_v2ray_xray_zip_path}")
  endif()

  if(_dart_v2ray_xray_sha256 STREQUAL "" AND NOT _dart_v2ray_xray_dgst_url STREQUAL "")
    set(_dart_v2ray_xray_dgst_path "${_dart_v2ray_download_dir}/Xray-windows-64.zip.dgst")
    file(DOWNLOAD "${_dart_v2ray_xray_dgst_url}" "${_dart_v2ray_xray_dgst_path}"
      STATUS _dart_v2ray_dgst_status
      LOG _dart_v2ray_dgst_log
      TLS_VERIFY ON)
    list(GET _dart_v2ray_dgst_status 0 _dart_v2ray_dgst_code)
    if(_dart_v2ray_dgst_code EQUAL 0)
      file(READ "${_dart_v2ray_xray_dgst_path}" _dart_v2ray_dgst_content)
      string(REGEX MATCH "sha256:([0-9a-fA-F]{64})" _dart_v2ray_dgst_match
        "${_dart_v2ray_dgst_content}")
      if(DEFINED CMAKE_MATCH_1 AND NOT "${CMAKE_MATCH_1}" STREQUAL "")
        set(_dart_v2ray_xray_sha256 "${CMAKE_MATCH_1}")
      endif()
    endif()
  endif()

  _dart_v2ray_verify_sha256(
    "${_dart_v2ray_xray_zip_path}"
    "${_dart_v2ray_xray_sha256}"
    "Xray-windows-64.zip")

  set(_dart_v2ray_extract_dir "${_dart_v2ray_download_dir}/xray_windows_extract")
  file(REMOVE_RECURSE "${_dart_v2ray_extract_dir}")
  file(MAKE_DIRECTORY "${_dart_v2ray_extract_dir}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xvf "${_dart_v2ray_xray_zip_path}"
    WORKING_DIRECTORY "${_dart_v2ray_extract_dir}"
    RESULT_VARIABLE _dart_v2ray_extract_result
    OUTPUT_VARIABLE _dart_v2ray_extract_stdout
    ERROR_VARIABLE _dart_v2ray_extract_stderr)
  if(NOT _dart_v2ray_extract_result EQUAL 0)
    message(FATAL_ERROR
      "dart_v2ray: failed to extract ${_dart_v2ray_xray_zip_path}. "
      "stdout=${_dart_v2ray_extract_stdout} stderr=${_dart_v2ray_extract_stderr}")
  endif()

  file(GLOB_RECURSE _dart_v2ray_downloaded_xray_candidates
    LIST_DIRECTORIES false
    "${_dart_v2ray_extract_dir}/xray.exe")
  file(GLOB_RECURSE _dart_v2ray_downloaded_wintun_candidates
    LIST_DIRECTORIES false
    "${_dart_v2ray_extract_dir}/wintun.dll")
  file(GLOB_RECURSE _dart_v2ray_downloaded_geoip_candidates
    LIST_DIRECTORIES false
    "${_dart_v2ray_extract_dir}/geoip.dat")
  file(GLOB_RECURSE _dart_v2ray_downloaded_geosite_candidates
    LIST_DIRECTORIES false
    "${_dart_v2ray_extract_dir}/geosite.dat")

  _dart_v2ray_select_existing(_dart_v2ray_downloaded_xray
    ${_dart_v2ray_downloaded_xray_candidates})
  _dart_v2ray_select_existing(_dart_v2ray_downloaded_wintun
    ${_dart_v2ray_downloaded_wintun_candidates})
  _dart_v2ray_select_existing(_dart_v2ray_downloaded_geoip
    ${_dart_v2ray_downloaded_geoip_candidates})
  _dart_v2ray_select_existing(_dart_v2ray_downloaded_geosite
    ${_dart_v2ray_downloaded_geosite_candidates})

  if(NOT _dart_v2ray_downloaded_xray STREQUAL "")
    file(COPY "${_dart_v2ray_downloaded_xray}" DESTINATION "${_dart_v2ray_runtime_dir}")
    set(_dart_v2ray_xray_executable "${_dart_v2ray_runtime_dir}/xray.exe")
  endif()
  if(NOT _dart_v2ray_downloaded_wintun STREQUAL "")
    file(COPY "${_dart_v2ray_downloaded_wintun}" DESTINATION "${_dart_v2ray_runtime_dir}")
    set(_dart_v2ray_wintun_dll "${_dart_v2ray_runtime_dir}/wintun.dll")
  endif()
  if(NOT _dart_v2ray_downloaded_geoip STREQUAL "")
    file(COPY "${_dart_v2ray_downloaded_geoip}" DESTINATION "${_dart_v2ray_runtime_dir}")
    set(_dart_v2ray_geoip_dat "${_dart_v2ray_runtime_dir}/geoip.dat")
  endif()
  if(NOT _dart_v2ray_downloaded_geosite STREQUAL "")
    file(COPY "${_dart_v2ray_downloaded_geosite}" DESTINATION "${_dart_v2ray_runtime_dir}")
    set(_dart_v2ray_geosite_dat "${_dart_v2ray_runtime_dir}/geosite.dat")
  endif()
endif()

if(_dart_v2ray_xray_executable STREQUAL "")
  message(FATAL_ERROR
    "dart_v2ray: xray.exe not found. Provide windows/bin/xray.exe "
    "or set DART_V2RAY_WINDOWS_XRAY_ZIP_PATH / DART_V2RAY_WINDOWS_XRAY_ZIP_URL.")
endif()

list(APPEND dart_v2ray_bundled_libraries "${_dart_v2ray_xray_executable}")
message(STATUS "dart_v2ray: bundling xray.exe from ${_dart_v2ray_xray_executable}")

if(NOT _dart_v2ray_wintun_dll STREQUAL "")
  list(APPEND dart_v2ray_bundled_libraries "${_dart_v2ray_wintun_dll}")
  message(STATUS "dart_v2ray: bundling wintun.dll from ${_dart_v2ray_wintun_dll}")
else()
  message(WARNING
    "dart_v2ray: wintun.dll was not found. Windows requireTun=true will fail "
    "unless wintun.dll is provided at runtime.")
endif()

if(NOT _dart_v2ray_geoip_dat STREQUAL "")
  list(APPEND dart_v2ray_bundled_libraries "${_dart_v2ray_geoip_dat}")
  message(STATUS "dart_v2ray: bundling geoip.dat from ${_dart_v2ray_geoip_dat}")
endif()

if(NOT _dart_v2ray_geosite_dat STREQUAL "")
  list(APPEND dart_v2ray_bundled_libraries "${_dart_v2ray_geosite_dat}")
  message(STATUS "dart_v2ray: bundling geosite.dat from ${_dart_v2ray_geosite_dat}")
endif()

list(REMOVE_DUPLICATES dart_v2ray_bundled_libraries)

set(dart_v2ray_bundled_libraries
  ${dart_v2ray_bundled_libraries}
  PARENT_SCOPE
)
