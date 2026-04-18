#ifndef FLUTTER_PLUGIN_DESKTOP_V2RAY_CORE_H_
#define FLUTTER_PLUGIN_DESKTOP_V2RAY_CORE_H_

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace dart_v2ray {

class DesktopV2rayCore {
 public:
  struct StartOptions {
    bool proxy_only = false;
    std::optional<int> auto_disconnect_seconds;
    std::vector<std::string> bypass_subnets;
    std::vector<std::string> dns_servers;
    bool require_tun = false;
  };

  struct WindowsDebugLoggingOptions {
    bool enable_file_logging = false;
    bool enable_verbose_logging = false;
    bool capture_xray_stdio = false;
    bool clear_existing_logs = false;
  };

  DesktopV2rayCore();
  ~DesktopV2rayCore();

  std::string Initialize();
  bool IsElevated() const;

  std::string Start(const std::string& config, const StartOptions& options);
  std::string Stop(bool from_auto_disconnect = false);
  std::string GetCoreVersion();
  void ConfigureWindowsDebugLogging(const WindowsDebugLoggingOptions& options);
  int GetServerDelay(const std::string& url) const;
  int GetConnectedServerDelay(const std::string& url) const;
  void PollProcessAndHandleExit();

  int UpdateAutoDisconnectTime(int additional_seconds);
  int GetRemainingAutoDisconnectTime() const;
  void CancelAutoDisconnect();
  bool WasAutoDisconnected() const;
  void ClearAutoDisconnectFlag();
  int64_t GetAutoDisconnectTimestamp() const;

  std::vector<std::string> BuildStatusPayload() const;
  std::map<std::string, std::string> GetWindowsTrafficDebugInfo() const;
  std::map<std::string, std::string> GetWindowsDebugLogs(int max_bytes = 16384) const;

 private:
  struct ProcessHandle;
  struct RuntimePaths {
    std::string xray_executable;
    std::string wintun_dll;
  };

  std::unique_ptr<ProcessHandle> process_;
  RuntimePaths runtime_paths_;
  std::string config_path_;

  mutable std::mutex mutex_;
  std::condition_variable timer_cv_;
  bool stop_timer_ = false;
  std::thread auto_disconnect_thread_;

  std::string state_ = "DISCONNECTED";
  std::string transport_mode_ = "idle";
  std::chrono::steady_clock::time_point connected_at_;
  std::optional<std::chrono::steady_clock::time_point> auto_disconnect_deadline_;
  bool auto_disconnected_ = false;
  int64_t auto_disconnect_timestamp_ms_ = 0;

#if defined(_WIN32)
  std::optional<unsigned int> tun_interface_index_;
  std::optional<unsigned int> upstream_interface_index_;
  mutable std::string last_traffic_source_ = "none";
  mutable std::string last_traffic_reason_ = "not_connected";
  mutable bool last_tun_counter_read_ok_ = false;
  mutable bool last_process_counter_read_ok_ = false;
  mutable bool last_upstream_counter_read_ok_ = false;
  mutable uint32_t last_tun_upload_counter_raw_ = 0;
  mutable uint32_t last_tun_download_counter_raw_ = 0;
  mutable uint64_t last_process_upload_counter_raw_ = 0;
  mutable uint64_t last_process_download_counter_raw_ = 0;
  mutable uint32_t last_upstream_upload_counter_raw_ = 0;
  mutable uint32_t last_upstream_download_counter_raw_ = 0;
#endif
  mutable uint32_t last_upload_counter_sample_ = 0;
  mutable uint32_t last_download_counter_sample_ = 0;
  mutable uint64_t accumulated_upload_bytes_ = 0;
  mutable uint64_t accumulated_download_bytes_ = 0;
  mutable std::chrono::steady_clock::time_point last_traffic_sample_at_;
  mutable bool has_traffic_sample_ = false;
  mutable uint64_t last_process_upload_counter_sample_ = 0;
  mutable uint64_t last_process_download_counter_sample_ = 0;
  mutable uint64_t accumulated_process_upload_bytes_ = 0;
  mutable uint64_t accumulated_process_download_bytes_ = 0;
  mutable std::chrono::steady_clock::time_point last_process_traffic_sample_at_;
  mutable bool has_process_traffic_sample_ = false;
  mutable uint32_t last_upstream_upload_counter_sample_ = 0;
  mutable uint32_t last_upstream_download_counter_sample_ = 0;
  mutable uint64_t accumulated_upstream_upload_bytes_ = 0;
  mutable uint64_t accumulated_upstream_download_bytes_ = 0;
  mutable std::chrono::steady_clock::time_point last_upstream_traffic_sample_at_;
  mutable bool has_upstream_traffic_sample_ = false;

  std::vector<std::string> configured_route_delete_commands_;
  std::string configured_dns_interface_;

  std::string BuildTempConfigPath() const;
  bool WriteConfig(const std::string& config);

  RuntimePaths DiscoverRuntimePaths() const;
  std::string ValidateRuntime(const RuntimePaths& paths, bool tun_requested) const;

  std::string BuildEffectiveConfig(const std::string& base_config,
                                   const StartOptions& options,
                                   bool* use_tun,
                                   std::string* mode_note) const;

  bool ApplyTunNetworking(const StartOptions& options,
                          const std::string& effective_config,
                          std::string* error);
  void CleanupTunNetworking();
  std::string ExecuteSystemCommand(const std::string& command) const;
  bool IsProcessRunning() const;

  static int MeasureTcpDelay(const std::string& url);
  void StartAutoDisconnectTimer();
  void StopAutoDisconnectTimer();
};

}  // namespace dart_v2ray

#endif  // FLUTTER_PLUGIN_DESKTOP_V2RAY_CORE_H_

