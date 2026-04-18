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

set(dart_v2ray_bundled_libraries "")

# Allow Windows runtime binaries to live either in the plugin package itself
# or in the consuming app's windows/ tree.
set(_dart_v2ray_xray_candidates
  "${CMAKE_CURRENT_SOURCE_DIR}/bin/xray.exe"
  "${CMAKE_SOURCE_DIR}/bin/xray.exe"
  "${CMAKE_SOURCE_DIR}/runner/bin/xray.exe")
foreach(_candidate IN LISTS _dart_v2ray_xray_candidates)
  if(EXISTS "${_candidate}")
    list(APPEND dart_v2ray_bundled_libraries "${_candidate}")
    message(STATUS "dart_v2ray: bundling xray.exe from ${_candidate}")
    break()
  endif()
endforeach()

set(_dart_v2ray_wintun_candidates
  "${CMAKE_CURRENT_SOURCE_DIR}/bin/wintun.dll"
  "${CMAKE_SOURCE_DIR}/bin/wintun.dll"
  "${CMAKE_SOURCE_DIR}/runner/bin/wintun.dll")
foreach(_candidate IN LISTS _dart_v2ray_wintun_candidates)
  if(EXISTS "${_candidate}")
    list(APPEND dart_v2ray_bundled_libraries "${_candidate}")
    message(STATUS "dart_v2ray: bundling wintun.dll from ${_candidate}")
    break()
  endif()
endforeach()

list(REMOVE_DUPLICATES dart_v2ray_bundled_libraries)

set(dart_v2ray_bundled_libraries
  ${dart_v2ray_bundled_libraries}
  PARENT_SCOPE
)
