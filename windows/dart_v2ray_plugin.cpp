#include "dart_v2ray_plugin.h"

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <shellapi.h>

#include <chrono>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

namespace dart_v2ray {

namespace {

const char kMethodChannelName[] = "dart_v2ray";
const char kStatusChannelName[] = "dart_v2ray/status";
constexpr UINT_PTR kStatusTimerBaseId = 0xF2A0;
constexpr UINT kStatusTimerIntervalMs = 1000;
constexpr auto kConnectedStatusMinInterval = std::chrono::seconds(1);
constexpr auto kStatusHeartbeatInterval = std::chrono::seconds(5);

void DebugStatusPayload(const std::vector<std::string>& payload) {
#if defined(_WIN32)
  std::ostringstream stream;
  stream << "[dart_v2ray/windows-plugin] status_emit";
  if (payload.size() > 5) stream << " state=" << payload[5];
  if (payload.size() > 7) stream << " phase=" << payload[7];
  if (payload.size() > 8) stream << " transport=" << payload[8];
  if (payload.size() > 9) stream << " source=" << payload[9];
  if (payload.size() > 10) stream << " reason=" << payload[10];
  if (payload.size() > 11) stream << " process=" << payload[11];
  stream << '\n';
  const std::string line = stream.str();
  OutputDebugStringA(line.c_str());
#else
  (void)payload;
#endif
}

std::optional<int> ExtractAutoDisconnectDuration(const flutter::EncodableMap& args) {
  const auto auto_disconnect_it = args.find(flutter::EncodableValue("auto_disconnect"));
  if (auto_disconnect_it == args.end() ||
      !std::holds_alternative<flutter::EncodableMap>(auto_disconnect_it->second)) {
    return std::nullopt;
  }

  const auto& map = std::get<flutter::EncodableMap>(auto_disconnect_it->second);
  const auto duration_it = map.find(flutter::EncodableValue("duration"));
  if (duration_it == map.end() || !std::holds_alternative<int32_t>(duration_it->second)) {
    return std::nullopt;
  }

  const int duration = std::get<int32_t>(duration_it->second);
  return duration > 0 ? std::optional<int>(duration) : std::nullopt;
}

std::vector<std::string> ExtractStringList(const flutter::EncodableMap& args, const char* key) {
  std::vector<std::string> values;
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end() || !std::holds_alternative<flutter::EncodableList>(it->second)) {
    return values;
  }

  const auto& list = std::get<flutter::EncodableList>(it->second);
  values.reserve(list.size());
  for (const auto& item : list) {
    if (std::holds_alternative<std::string>(item)) {
      values.push_back(std::get<std::string>(item));
    }
  }
  return values;
}

bool ExtractBool(const flutter::EncodableMap& args, const char* key, bool fallback) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it != args.end() && std::holds_alternative<bool>(it->second)) {
    return std::get<bool>(it->second);
  }
  return fallback;
}

std::optional<bool> ExtractOptionalBool(const flutter::EncodableMap& args, const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it != args.end() && std::holds_alternative<bool>(it->second)) {
    return std::optional<bool>(std::get<bool>(it->second));
  }
  return std::nullopt;
}

int ExtractInt(const flutter::EncodableMap& args, const char* key, int fallback) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it != args.end() && std::holds_alternative<int32_t>(it->second)) {
    return std::get<int32_t>(it->second);
  }
  return fallback;
}

bool RestartAsAdmin() {
  wchar_t exe_path[MAX_PATH];
  if (GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) {
    return false;
  }

  wchar_t* cmd_line = GetCommandLineW();
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(cmd_line, &argc);
  if (!argv) {
    return false;
  }

  std::wstring params;
  for (int i = 1; i < argc; ++i) {
    if (i > 1) {
      params += L" ";
    }
    if (std::wcschr(argv[i], L' ')) {
      params += L"\"";
      params += argv[i];
      params += L"\"";
    } else {
      params += argv[i];
    }
  }
  LocalFree(argv);

  HINSTANCE result = ShellExecuteW(nullptr, L"runas", exe_path,
                                   params.empty() ? nullptr : params.c_str(),
                                   nullptr, SW_SHOWNORMAL);
  return reinterpret_cast<intptr_t>(result) > 32;
}

}  // namespace

DartV2rayPlugin::DartV2rayPlugin() = default;

DartV2rayPlugin::~DartV2rayPlugin() {
  StopStatusThread();
  if (registrar_ != nullptr && window_proc_delegate_id_ != 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_);
  }
}

void DartV2rayPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto method_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kMethodChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  auto status_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), kStatusChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<DartV2rayPlugin>();
  plugin->registrar_ = registrar;

  method_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  status_channel->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments,
                                          std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            (void)arguments;
            {
              std::lock_guard<std::mutex> lock(plugin_pointer->sink_mutex_);
              plugin_pointer->status_sink_ = std::move(events);
            }
            plugin_pointer->StartStatusThread();
            return nullptr;
          },
          [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            (void)arguments;
            {
              std::lock_guard<std::mutex> lock(plugin_pointer->sink_mutex_);
              plugin_pointer->status_sink_.reset();
            }
            plugin_pointer->StopStatusThread();
            return nullptr;
          }));

  registrar->AddPlugin(std::move(plugin));
}

void DartV2rayPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string method_name = method_call.method_name();

  if (method_name == "requestPermission") {
    const bool elevated = core_.IsElevated();
    if (!elevated) {
      if (RestartAsAdmin()) {
        exit(0);
      }
    }
    result->Success(flutter::EncodableValue(elevated));
    return;
  }

  if (method_name == "initializeVless") {
    const std::string init_error = core_.Initialize();
    if (!init_error.empty()) {
      result->Error("initialize_failed", init_error);
      return;
    }
    result->Success();
    return;
  }

  if (method_name == "configureWindowsDebugLogging") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("invalid_arguments", "configureWindowsDebugLogging requires a map argument.");
      return;
    }

    DesktopV2rayCore::WindowsDebugLoggingOptions options;
    options.enable_file_logging = ExtractBool(*args, "enable_file_log", false);
    options.enable_verbose_logging = ExtractBool(*args, "enable_verbose_log", false);
    options.capture_xray_stdio = ExtractBool(*args, "capture_xray_io", false);
    options.clear_existing_logs = ExtractBool(*args, "clear_existing_logs", false);
    core_.ConfigureWindowsDebugLogging(options);
    result->Success();
    return;
  }

  if (method_name == "startVless") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("invalid_arguments", "startVless requires a map argument.");
      return;
    }

    const auto config_it = args->find(flutter::EncodableValue("config"));
    if (config_it == args->end() || !std::holds_alternative<std::string>(config_it->second)) {
      result->Error("invalid_arguments", "Missing config JSON string.");
      return;
    }

    DesktopV2rayCore::StartOptions options;
    options.auto_disconnect_seconds = ExtractAutoDisconnectDuration(*args);
    options.bypass_subnets = ExtractStringList(*args, "bypass_subnets");
    options.dns_servers = ExtractStringList(*args, "dns_servers");
    const std::optional<bool> require_tun = ExtractOptionalBool(*args, "require_tun");
    const std::optional<bool> legacy_require_tun =
        ExtractOptionalBool(*args, "windows_require_tun");
    const std::optional<bool> proxy_only = ExtractOptionalBool(*args, "proxy_only");

    bool effective_require_tun = false;
    if (require_tun.has_value()) {
      effective_require_tun = *require_tun;
    } else if (legacy_require_tun.has_value()) {
      effective_require_tun = *legacy_require_tun;
    } else if (proxy_only.has_value()) {
      effective_require_tun = !(*proxy_only);
    }

    options.require_tun = effective_require_tun;
    options.proxy_only = !effective_require_tun;

    const std::string error = core_.Start(std::get<std::string>(config_it->second), options);
    if (!error.empty()) {
      // Publish immediate ERROR/terminal snapshot instead of waiting for timer tick.
      PublishStatus();
      result->Error("start_failed", error);
      return;
    }

    // Publish immediate CONNECTING/CONNECTED snapshot instead of waiting for timer tick.
    PublishStatus();
    result->Success();
    return;
  }

  if (method_name == "stopVless") {
    const std::string error = core_.Stop();
    if (!error.empty()) {
      result->Error("stop_failed", error);
      return;
    }
    // Publish immediate DISCONNECTED/AUTO_DISCONNECTED snapshot.
    PublishStatus();
    result->Success();
    return;
  }

  if (method_name == "getCoreVersion") {
    result->Success(flutter::EncodableValue(core_.GetCoreVersion()));
    return;
  }

  if (method_name == "getServerDelay") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    const auto url = (args != nullptr && args->count(flutter::EncodableValue("url")) > 0 &&
                      std::holds_alternative<std::string>(args->at(flutter::EncodableValue("url"))))
                         ? std::get<std::string>(args->at(flutter::EncodableValue("url")))
                         : "https://google.com/generate_204";
    result->Success(flutter::EncodableValue(core_.GetServerDelay(url)));
    return;
  }

  if (method_name == "getConnectedServerDelay") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    const auto url = (args != nullptr && args->count(flutter::EncodableValue("url")) > 0 &&
                      std::holds_alternative<std::string>(args->at(flutter::EncodableValue("url"))))
                         ? std::get<std::string>(args->at(flutter::EncodableValue("url")))
                         : "https://google.com/generate_204";
    result->Success(flutter::EncodableValue(core_.GetConnectedServerDelay(url)));
    return;
  }

  if (method_name == "updateAutoDisconnectTime") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    int additional_seconds = 0;
    if (args != nullptr) {
      const auto it = args->find(flutter::EncodableValue("additional_seconds"));
      if (it != args->end() && std::holds_alternative<int32_t>(it->second)) {
        additional_seconds = std::get<int32_t>(it->second);
      }
    }
    result->Success(flutter::EncodableValue(core_.UpdateAutoDisconnectTime(additional_seconds)));
    return;
  }

  if (method_name == "getRemainingAutoDisconnectTime") {
    result->Success(flutter::EncodableValue(core_.GetRemainingAutoDisconnectTime()));
    return;
  }

  if (method_name == "cancelAutoDisconnect") {
    core_.CancelAutoDisconnect();
    result->Success();
    return;
  }

  if (method_name == "wasAutoDisconnected") {
    result->Success(flutter::EncodableValue(core_.WasAutoDisconnected()));
    return;
  }

  if (method_name == "clearAutoDisconnectFlag") {
    core_.ClearAutoDisconnectFlag();
    result->Success();
    return;
  }

  if (method_name == "getAutoDisconnectTimestamp") {
    result->Success(flutter::EncodableValue(core_.GetAutoDisconnectTimestamp()));
    return;
  }

  if (method_name == "getWindowsTrafficSource") {
    core_.PollProcessAndHandleExit();
    const auto diagnostics = core_.GetWindowsTrafficDebugInfo();
    flutter::EncodableMap payload;
    for (const auto& entry : diagnostics) {
      payload[flutter::EncodableValue(entry.first)] =
          flutter::EncodableValue(entry.second);
    }
    result->Success(flutter::EncodableValue(payload));
    return;
  }

  if (method_name == "getWindowsDebugLogs") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    const int max_bytes = args != nullptr ? ExtractInt(*args, "max_bytes", 16384) : 16384;
    core_.PollProcessAndHandleExit();
    const auto diagnostics = core_.GetWindowsDebugLogs(max_bytes);
    flutter::EncodableMap payload;
    for (const auto& entry : diagnostics) {
      payload[flutter::EncodableValue(entry.first)] =
          flutter::EncodableValue(entry.second);
    }
    result->Success(flutter::EncodableValue(payload));
    return;
  }

  result->NotImplemented();
}

void DartV2rayPlugin::StartStatusThread() {
  if (status_thread_running_.exchange(true)) {
    return;
  }

  if (registrar_ == nullptr || registrar_->GetView() == nullptr) {
    status_thread_running_ = false;
    return;
  }

  if (window_proc_delegate_id_ == 0) {
    window_proc_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND hwnd, UINT message, WPARAM wparam,
               LPARAM lparam) -> std::optional<LRESULT> {
          return HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
        });
  }

  {
    std::lock_guard<std::mutex> lock(sink_mutex_);
    last_status_payload_.clear();
    last_status_state_.clear();
    has_published_status_ = false;
    last_status_published_at_ = std::chrono::steady_clock::time_point{};
  }

  status_timer_id_ = kStatusTimerBaseId + reinterpret_cast<UINT_PTR>(this);
  SetTimer(registrar_->GetView()->GetNativeWindow(), status_timer_id_,
           kStatusTimerIntervalMs, nullptr);
}

void DartV2rayPlugin::StopStatusThread() {
  if (!status_thread_running_.exchange(false)) {
    return;
  }

  if (registrar_ != nullptr && registrar_->GetView() != nullptr &&
      status_timer_id_ != 0) {
    KillTimer(registrar_->GetView()->GetNativeWindow(), status_timer_id_);
  }
  status_timer_id_ = 0;

  std::lock_guard<std::mutex> lock(sink_mutex_);
  last_status_payload_.clear();
  last_status_state_.clear();
  has_published_status_ = false;
  last_status_published_at_ = std::chrono::steady_clock::time_point{};
}

void DartV2rayPlugin::PublishStatus() {
  core_.PollProcessAndHandleExit();

  const auto payload = core_.BuildStatusPayload();
  const auto now = std::chrono::steady_clock::now();
  const std::string state = payload.size() > 5 ? payload[5] : "";

  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (!status_sink_) {
    return;
  }

  if (has_published_status_) {
    const bool state_changed = state != last_status_state_;
    if (!state_changed) {
      if (state == "CONNECTED" &&
          (now - last_status_published_at_) < kConnectedStatusMinInterval) {
        return;
      }
      if (payload == last_status_payload_) {
        if ((now - last_status_published_at_) < kStatusHeartbeatInterval) {
          return;
        }
      }
    }
  }

  flutter::EncodableList list;
  for (const auto& part : payload) {
    list.emplace_back(part);
  }
  DebugStatusPayload(payload);
  status_sink_->Success(flutter::EncodableValue(list));

  last_status_payload_ = payload;
  last_status_state_ = state;
  last_status_published_at_ = now;
  has_published_status_ = true;
}

std::optional<LRESULT> DartV2rayPlugin::HandleTopLevelWindowProc(
    HWND /*hwnd*/, UINT message, WPARAM wparam, LPARAM /*lparam*/) {
  if (!status_thread_running_) {
    return std::nullopt;
  }

  if (message == WM_TIMER && status_timer_id_ != 0 && wparam == status_timer_id_) {
    PublishStatus();
    return 0;
  }

  return std::nullopt;
}

}  // namespace dart_v2ray
