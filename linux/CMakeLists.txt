cmake_minimum_required(VERSION 3.14)
project(dart_v2ray_plugin LANGUAGES CXX)

find_package(Threads REQUIRED)

add_library(dart_v2ray_plugin SHARED
  "dart_v2ray_plugin.cc"
  "../shared/desktop_v2ray_core.cc"
)

apply_standard_settings(dart_v2ray_plugin)

set_target_properties(dart_v2ray_plugin PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(dart_v2ray_plugin PRIVATE FLUTTER_PLUGIN_IMPL)
target_compile_features(dart_v2ray_plugin PRIVATE cxx_std_17)

target_include_directories(dart_v2ray_plugin INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(dart_v2ray_plugin PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../shared")

target_link_libraries(dart_v2ray_plugin PRIVATE flutter Threads::Threads)

set(dart_v2ray_bundled_libraries
  dart_v2ray_plugin
  PARENT_SCOPE
)

