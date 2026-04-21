#ifndef FLUTTER_PLUGIN_DART_V2RAY_PLUGIN_H_
#define FLUTTER_PLUGIN_DART_V2RAY_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "desktop_v2ray_core.h"

namespace dart_v2ray {

class DartV2rayPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  DartV2rayPlugin();
  ~DartV2rayPlugin() override;

  DartV2rayPlugin(const DartV2rayPlugin&) = delete;
  DartV2rayPlugin& operator=(const DartV2rayPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void StartStatusThread();
  void StopStatusThread();
  void PublishStatus();
  std::optional<LRESULT> HandleTopLevelWindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                                   LPARAM lparam);

  DesktopV2rayCore core_;
  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  std::atomic<bool> status_thread_running_{false};
  int window_proc_delegate_id_ = 0;
  std::thread status_thread_;
  std::mutex sink_mutex_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> status_sink_;
  std::vector<std::string> last_status_payload_;
  std::string last_status_state_;
  std::chrono::steady_clock::time_point last_status_published_at_;
  bool has_published_status_ = false;
};

}  // namespace dart_v2ray

#endif  // FLUTTER_PLUGIN_DART_V2RAY_PLUGIN_H_

