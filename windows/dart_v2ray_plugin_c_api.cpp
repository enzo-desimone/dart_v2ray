#include "dart_v2ray/dart_v2ray_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "dart_v2ray_plugin.h"

void DartV2rayPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  dart_v2ray::DartV2rayPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

