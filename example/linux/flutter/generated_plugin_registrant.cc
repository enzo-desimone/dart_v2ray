//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <dart_v2ray/dart_v2ray_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) dart_v2ray_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "DartV2rayPlugin");
  dart_v2ray_plugin_register_with_registrar(dart_v2ray_registrar);
}
