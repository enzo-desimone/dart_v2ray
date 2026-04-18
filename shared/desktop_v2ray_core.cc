#include "desktop_v2ray_core.h"

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <limits>
#include <regex>
#include <set>
#include <sstream>

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <Windows.h>
#include <iphlpapi.h>
#include <Ws2tcpip.h>
#pragma comment(lib, "Ws2_32.lib")
#pragma comment(lib, "Iphlpapi.lib")
#else
#include <arpa/inet.h>
#include <csignal>
#include <cstdio>
#include <filesystem>
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

namespace dart_v2ray {

#if defined(_WIN32)
namespace {
bool FileExists(const std::string& path) {
  const DWORD attributes = GetFileAttributesA(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::string GetExecutableDirectory() {
  char module_path[MAX_PATH];
  const DWORD length = GetModuleFileNameA(nullptr, module_path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return "";
  }

  std::string path(module_path, length);
  const auto separator = path.find_last_of("\\/");
  if (separator == std::string::npos) {
    return "";
  }
  return path.substr(0, separator);
}

std::string GetCurrentModuleDirectory() {
  HMODULE module = nullptr;
  if (!GetModuleHandleExA(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          reinterpret_cast<LPCSTR>(&GetCurrentModuleDirectory), &module) ||
      module == nullptr) {
    return "";
  }

  char module_path[MAX_PATH];
  const DWORD length = GetModuleFileNameA(module, module_path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return "";
  }

  std::string path(module_path, length);
  const auto separator = path.find_last_of("\\/");
  if (separator == std::string::npos) {
    return "";
  }
  return path.substr(0, separator);
}

std::string Win32ErrorToString(DWORD error_code) {
  LPSTR message_buffer = nullptr;
  const DWORD size = FormatMessageA(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
          FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, error_code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      reinterpret_cast<LPSTR>(&message_buffer), 0, nullptr);

  if (size == 0 || message_buffer == nullptr) {
    return "Unknown Win32 error";
  }

  std::string message(message_buffer, size);
  LocalFree(message_buffer);

  while (!message.empty() &&
         (message.back() == '\r' || message.back() == '\n' || message.back() == ' ')) {
    message.pop_back();
  }

  return message;
}

std::string GetEnv(const char* name);

bool IsTruthyEnvValue(const std::string& value) {
  return value == "1" || value == "true" || value == "TRUE" || value == "yes" ||
         value == "YES" || value == "on" || value == "ON";
}

std::atomic<bool>& FileLoggingEnabledFlag() {
  static std::atomic<bool> enabled{IsTruthyEnvValue(GetEnv("DART_V2RAY_WINDOWS_FILE_LOG"))};
  return enabled;
}

std::atomic<bool>& VerboseLoggingEnabledFlag() {
  static std::atomic<bool> enabled{IsTruthyEnvValue(GetEnv("DART_V2RAY_WINDOWS_VERBOSE_LOG"))};
  return enabled;
}

std::atomic<bool>& XrayStdIoCaptureEnabledFlag() {
  static std::atomic<bool> enabled{
      IsTruthyEnvValue(GetEnv("DART_V2RAY_WINDOWS_CAPTURE_XRAY_IO"))};
  return enabled;
}

bool IsFileLoggingEnabled() {
  return FileLoggingEnabledFlag().load();
}

bool IsVerboseLoggingEnabled() {
  return VerboseLoggingEnabledFlag().load();
}

bool IsXrayStdIoCaptureEnabled() {
  return XrayStdIoCaptureEnabledFlag().load();
}

void SetFileLoggingEnabled(bool enabled) {
  FileLoggingEnabledFlag().store(enabled);
}

void SetVerboseLoggingEnabled(bool enabled) {
  VerboseLoggingEnabledFlag().store(enabled);
}

void SetXrayStdIoCaptureEnabled(bool enabled) {
  XrayStdIoCaptureEnabledFlag().store(enabled);
}

std::string BoolToString(bool value) {
  return value ? "true" : "false";
}

std::string BuildTempFilePath(const char* file_name) {
  char temp_path[MAX_PATH];
  if (GetTempPathA(MAX_PATH, temp_path) == 0) {
    return "";
  }
  return std::string(temp_path) + file_name;
}

std::string GetPluginLogPath() {
  return BuildTempFilePath("dart_v2ray.log");
}

std::string GetXrayCaptureLogPath() {
  return BuildTempFilePath("dart_v2ray_xray.log");
}

void ClearDebugLogFile(const std::string& path) {
  if (path.empty() || !FileExists(path)) {
    return;
  }
  DeleteFileA(path.c_str());
}

std::string ReadFileTail(const std::string& path, size_t max_bytes) {
  if (path.empty()) {
    return "";
  }

  std::ifstream input(path, std::ios::binary | std::ios::ate);
  if (!input.is_open()) {
    return "";
  }

  const std::streamoff file_size = input.tellg();
  if (file_size <= 0) {
    return "";
  }

  const std::streamoff bounded_size =
      std::min<std::streamoff>(file_size, static_cast<std::streamoff>(max_bytes));
  input.seekg(file_size - bounded_size, std::ios::beg);

  std::string buffer(static_cast<size_t>(bounded_size), '\0');
  input.read(buffer.data(), bounded_size);
  buffer.resize(static_cast<size_t>(input.gcount()));
  return buffer;
}

void LogLine(const std::string& message) {
  const std::string line = "[dart_v2ray/windows] " + message + "\n";
  OutputDebugStringA(line.c_str());

  // Disk logging is opt-in to reduce I/O overhead in production.
  if (!IsFileLoggingEnabled()) {
    return;
  }

  const std::string log_path = GetPluginLogPath();
  if (log_path.empty()) {
    return;
  }

  FILE* f = nullptr;
  if (fopen_s(&f, log_path.c_str(), "a") == 0 && f != nullptr) {
    fprintf(f, "%s", line.c_str());
    fclose(f);
  }
}

std::string EscapeForCmd(const std::string& value) {
  std::string escaped;
  escaped.reserve(value.size() + 4);
  for (char c : value) {
    if (c == '"') {
      escaped += "\\\"";
    } else {
      escaped.push_back(c);
    }
  }
  return escaped;
}

std::string GetEnv(const char* name) {
  char* value = nullptr;
  size_t len = 0;
  if (_dupenv_s(&value, &len, name) == 0 && value != nullptr && len > 1) {
    std::string out(value);
    free(value);
    return out;
  }
  free(value);
  return "";
}

std::string FindBinaryFromPath(const std::string& file_name) {
  char path_buffer[MAX_PATH];
  const DWORD path_length =
      SearchPathA(nullptr, file_name.c_str(), nullptr, MAX_PATH, path_buffer, nullptr);
  if (path_length > 0 && path_length < MAX_PATH) {
    return std::string(path_buffer, path_length);
  }
  return "";
}

std::string BuildMissingXrayError() {
  return "xray.exe could not be located. Set XRAY_EXECUTABLE, add xray.exe to PATH, "
         "or bundle windows/bin/xray.exe with the plugin.";
}

size_t FindMatchingBracket(const std::string& input, size_t open_pos, char open_bracket,
                           char close_bracket) {
  int depth = 0;
  for (size_t i = open_pos; i < input.size(); ++i) {
    if (input[i] == open_bracket) {
      ++depth;
    } else if (input[i] == close_bracket) {
      --depth;
      if (depth == 0) {
        return i;
      }
    }
  }
  return std::string::npos;
}

size_t FindRootObjectEnd(const std::string& input) {
  bool in_string = false;
  bool escape = false;
  int depth = 0;
  for (size_t i = 0; i < input.size(); ++i) {
    char c = input[i];
    if (escape) {
      escape = false;
      continue;
    }
    if (c == '\\') {
      escape = true;
      continue;
    }
    if (c == '"') {
      in_string = !in_string;
      continue;
    }
    if (in_string) continue;
    if (c == '{') {
      ++depth;
    } else if (c == '}') {
      --depth;
      if (depth == 0) {
        return i;
      }
    }
  }
  return std::string::npos;
}

std::string FindPreferredOutboundTag(const std::string& config);

bool InsertTunInbound(std::string* config, const std::vector<std::string>& dns_servers) {
  const std::string inbound_tag = "\"tag\":\"dart_v2ray_tun_in\"";
  if (config->find(inbound_tag) != std::string::npos) {
    return true;
  }

  std::ostringstream tun_inbound;
  tun_inbound
      << "{"
      << "\"tag\":\"dart_v2ray_tun_in\"," 
      << "\"protocol\":\"tun\"," 
      << "\"settings\":{"
      << "\"name\":\"xray-wintun\"," 
      << "\"mtu\":1500," 
      << "\"stack\":\"gvisor\"," 
      << "\"endpointIndependentNat\":true," 
      << "\"sniffing\":true," 
      << "\"autoRoute\":false," 
      << "\"strictRoute\":true," 
      << "\"address\":[\"172.19.0.2/30\",\"fdfe:dcba:9876::2/126\"],"
      << "\"gateway\":\"172.19.0.1\"";

  if (!dns_servers.empty()) {
    tun_inbound << ",\"dns\":[";
    for (size_t i = 0; i < dns_servers.size(); ++i) {
      if (i > 0) {
        tun_inbound << ',';
      }
      tun_inbound << '"' << dns_servers[i] << '"';
    }
    tun_inbound << ']';
  }

  tun_inbound << "}}";

  const std::string key = "\"inbounds\"";
  const size_t key_pos = config->find(key);
  if (key_pos == std::string::npos) {
    const size_t root_end = FindRootObjectEnd(*config);
    if (root_end == std::string::npos) {
      return false;
    }

    const bool prepend_comma = root_end > 0 && (*config)[root_end - 1] != '{';
    config->insert(root_end,
                   (prepend_comma ? "," : "") +
                   std::string("\"inbounds\":[") + tun_inbound.str() + "]");
    return true;
  }

  size_t array_start = config->find('[', key_pos);
  if (array_start == std::string::npos) {
    return false;
  }
  size_t array_end = FindMatchingBracket(*config, array_start, '[', ']');
  if (array_end == std::string::npos) {
    return false;
  }

  const std::string array_body = config->substr(array_start + 1, array_end - array_start - 1);
  const bool empty = array_body.find_first_not_of(" \t\r\n") == std::string::npos;

  config->insert(array_end, (empty ? "" : ",") + tun_inbound.str());
  return true;
}

bool InjectDnsServers(std::string* config, const std::vector<std::string>& dns_servers) {
  std::vector<std::string> effective_dns = dns_servers;
  if (effective_dns.empty()) {
    effective_dns = {"8.8.8.8", "1.1.1.1"};
  }

  std::ostringstream servers;
  servers << "\"dns\":{\"servers\":[";
  for (size_t i = 0; i < effective_dns.size(); ++i) {
    if (i > 0) {
      servers << ',';
    }
    servers << '"' << effective_dns[i] << '"';
  }
  servers << "]}";

  const std::string dns_key = "\"dns\"";
  const size_t dns_pos = config->find(dns_key);
  if (dns_pos != std::string::npos) {
    size_t dns_obj_start = config->find('{', dns_pos);
    if (dns_obj_start == std::string::npos) {
      return false;
    }
    size_t dns_obj_end = FindMatchingBracket(*config, dns_obj_start, '{', '}');
    if (dns_obj_end == std::string::npos) {
      return false;
    }
    config->replace(dns_pos, dns_obj_end - dns_pos + 1, servers.str());
    return true;
  }

  const size_t root_end = FindRootObjectEnd(*config);
  if (root_end == std::string::npos) {
    return false;
  }

  const bool prepend_comma = root_end > 0 && (*config)[root_end - 1] != '{';
  config->insert(root_end, (prepend_comma ? "," : "") + servers.str());
  return true;
}

bool InjectTunRouting(std::string* config) {
  const std::string routing_key = "\"routing\"";
  const std::string outbound_tag = FindPreferredOutboundTag(*config);
  if (outbound_tag.empty()) {
    return false;
  }
  const std::string rule = "{\"type\":\"field\",\"inboundTag\":[\"dart_v2ray_tun_in\"],\"outboundTag\":\"" +
                           outbound_tag + "\"}";

  const size_t routing_pos = config->find(routing_key);
  if (routing_pos != std::string::npos) {
    size_t obj_start = config->find('{', routing_pos);
    if (obj_start == std::string::npos) return false;
    size_t rules_pos = config->find("\"rules\"", obj_start);
    if (rules_pos != std::string::npos) {
      size_t array_start = config->find('[', rules_pos);
      if (array_start == std::string::npos) return false;
      size_t array_end = FindMatchingBracket(*config, array_start, '[', ']');
      if (array_end == std::string::npos) return false;
      const std::string body = config->substr(array_start + 1, array_end - array_start - 1);
      const bool empty = body.find_first_not_of(" \t\r\n") == std::string::npos;
      config->insert(array_end, (empty ? "" : ",") + rule);
      return true;
    }
    // routing object exists but no rules array -> insert before closing brace
    size_t obj_end = FindMatchingBracket(*config, obj_start, '{', '}');
    if (obj_end == std::string::npos) return false;
    const std::string inner = config->substr(obj_start + 1, obj_end - obj_start - 1);
    const bool empty = inner.find_first_not_of(" \t\r\n") == std::string::npos;
    config->insert(obj_end, std::string(empty ? "" : ",") + "\"rules\":[" + rule + "]");
    return true;
  }

  const size_t root_end = FindRootObjectEnd(*config);
  if (root_end == std::string::npos) return false;
  const bool prepend_comma = root_end > 0 && (*config)[root_end - 1] != '{';
  config->insert(root_end,
                 (prepend_comma ? "," : "") +
                 std::string("\"routing\":{\"domainStrategy\":\"UseIp\",\"rules\":[") + rule + "]}");
  return true;
}

bool ParseIpv4Cidr(const std::string& cidr, std::string* network, std::string* netmask) {
  const size_t slash = cidr.find('/');
  if (slash == std::string::npos) {
    return false;
  }
  const std::string ip = cidr.substr(0, slash);
  const std::string prefix_str = cidr.substr(slash + 1);

  int prefix = 0;
  try {
    prefix = std::stoi(prefix_str);
  } catch (...) {
    return false;
  }
  if (prefix < 0 || prefix > 32) {
    return false;
  }

  IN_ADDR addr{};
  if (InetPtonA(AF_INET, ip.c_str(), &addr) != 1) {
    return false;
  }

  const uint32_t input = ntohl(addr.S_un.S_addr);
  const uint32_t mask = prefix == 0 ? 0 : (0xFFFFFFFFu << (32 - prefix));
  const uint32_t masked = input & mask;

  IN_ADDR masked_addr{};
  masked_addr.S_un.S_addr = htonl(masked);
  IN_ADDR mask_addr{};
  mask_addr.S_un.S_addr = htonl(mask);

  char network_buffer[INET_ADDRSTRLEN];
  char mask_buffer[INET_ADDRSTRLEN];
  if (InetNtopA(AF_INET, &masked_addr, network_buffer, sizeof(network_buffer)) == nullptr ||
      InetNtopA(AF_INET, &mask_addr, mask_buffer, sizeof(mask_buffer)) == nullptr) {
    return false;
  }

  *network = std::string(network_buffer);
  *netmask = std::string(mask_buffer);
  return true;
}

std::optional<unsigned int> FindInterfaceIndexByFriendlyName(const std::string& interface_name) {
  ULONG flags = GAA_FLAG_INCLUDE_PREFIX;
  ULONG family = AF_UNSPEC;
  ULONG out_buf_len = 15 * 1024;
  std::vector<unsigned char> buffer(out_buf_len);
  PIP_ADAPTER_ADDRESSES addresses =
      reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer.data());

  DWORD result = GetAdaptersAddresses(family, flags, nullptr, addresses, &out_buf_len);
  if (result == ERROR_BUFFER_OVERFLOW) {
    buffer.resize(out_buf_len);
    addresses = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer.data());
    result = GetAdaptersAddresses(family, flags, nullptr, addresses, &out_buf_len);
  }
  if (result != NO_ERROR) {
    return std::nullopt;
  }

  int wide_length = MultiByteToWideChar(CP_UTF8, 0, interface_name.c_str(), -1, nullptr, 0);
  if (wide_length <= 1) {
    return std::nullopt;
  }
  std::wstring wide_name(static_cast<size_t>(wide_length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, interface_name.c_str(), -1, wide_name.data(), wide_length);

  for (PIP_ADAPTER_ADDRESSES current = addresses; current != nullptr; current = current->Next) {
    if (current->FriendlyName == nullptr) {
      continue;
    }
    if (_wcsicmp(current->FriendlyName, wide_name.c_str()) == 0) {
      const unsigned int index = current->IfIndex != 0 ? current->IfIndex : current->Ipv6IfIndex;
      if (index != 0) {
        return index;
      }
    }
  }

  return std::nullopt;
}

bool IsLikelyRemoteHost(const std::string& host) {
  if (host.empty()) {
    return false;
  }

  if (host == "localhost" || host == "0.0.0.0" || host == "::1") {
    return false;
  }

  if (host.rfind("127.", 0) == 0 || host.rfind("169.254.", 0) == 0) {
    return false;
  }

  if (host.find('/') != std::string::npos || host.find(' ') != std::string::npos) {
    return false;
  }

  return true;
}

std::string ExtractOutboundsSlice(const std::string& config) {
  const std::string outbounds_key = "\"outbounds\"";
  const size_t outbounds_pos = config.find(outbounds_key);
  if (outbounds_pos == std::string::npos) {
    return "";
  }

  const size_t array_start = config.find('[', outbounds_pos);
  if (array_start == std::string::npos) {
    return "";
  }

  const size_t array_end = FindMatchingBracket(config, array_start, '[', ']');
  if (array_end == std::string::npos || array_end <= array_start) {
    return "";
  }

  return config.substr(array_start, array_end - array_start + 1);
}

bool HasUsableOutbounds(const std::string& config) {
  const std::string outbounds_slice = ExtractOutboundsSlice(config);
  if (outbounds_slice.empty()) {
    return false;
  }

  return outbounds_slice.find('{') != std::string::npos;
}

std::string FindPreferredOutboundTag(const std::string& config) {
  const std::string outbounds_slice = ExtractOutboundsSlice(config);
  if (outbounds_slice.empty()) {
    return "";
  }

  const std::regex tag_pattern("\"tag\"\\s*:\\s*\"([^\"]+)\"");
  std::string first_tag;
  for (std::sregex_iterator it(outbounds_slice.begin(), outbounds_slice.end(), tag_pattern), end;
       it != end; ++it) {
    const std::string tag = (*it)[1].str();
    if (first_tag.empty()) {
      first_tag = tag;
    }
    if (tag == "proxy") {
      return tag;
    }
  }

  return first_tag;
}

std::vector<std::string> ExtractOutboundDestinationHosts(const std::string& config) {
  std::vector<std::string> hosts;
  const std::string outbounds_slice = ExtractOutboundsSlice(config);
  if (outbounds_slice.empty()) {
    return hosts;
  }
  const std::regex address_pattern("\"address\"\\s*:\\s*\"([^\"]+)\"");

  std::set<std::string> unique;
  for (std::sregex_iterator it(outbounds_slice.begin(), outbounds_slice.end(), address_pattern),
                            end;
       it != end; ++it) {
    std::string host = (*it)[1].str();
    if (IsLikelyRemoteHost(host)) {
      unique.insert(host);
    }
  }

  hosts.assign(unique.begin(), unique.end());
  return hosts;
}

std::vector<std::string> ResolveHostToIpv4(const std::string& host) {
  std::set<std::string> ip_set;

  IN_ADDR ipv4{};
  if (InetPtonA(AF_INET, host.c_str(), &ipv4) == 1) {
    ip_set.insert(host);
  } else {
    addrinfo hints{};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo* result = nullptr;
    if (getaddrinfo(host.c_str(), nullptr, &hints, &result) == 0 && result != nullptr) {
      for (addrinfo* ptr = result; ptr != nullptr; ptr = ptr->ai_next) {
        if (ptr->ai_family != AF_INET) {
          continue;
        }
        auto* sockaddr = reinterpret_cast<sockaddr_in*>(ptr->ai_addr);
        char buffer[INET_ADDRSTRLEN];
        if (InetNtopA(AF_INET, &sockaddr->sin_addr, buffer, sizeof(buffer)) != nullptr) {
          ip_set.insert(std::string(buffer));
        }
      }
      freeaddrinfo(result);
    }
  }

  return std::vector<std::string>(ip_set.begin(), ip_set.end());
}

bool GetBestRouteForDestination(const std::string& destination_ip,
                                std::string* gateway,
                                unsigned int* interface_index) {
  IN_ADDR destination{};
  if (InetPtonA(AF_INET, destination_ip.c_str(), &destination) != 1) {
    return false;
  }

  MIB_IPFORWARDROW route{};
  if (GetBestRoute(destination.S_un.S_addr, 0, &route) != NO_ERROR) {
    return false;
  }

  IN_ADDR gateway_addr{};
  gateway_addr.S_un.S_addr = route.dwForwardNextHop;

  char gateway_buffer[INET_ADDRSTRLEN];
  if (InetNtopA(AF_INET, &gateway_addr, gateway_buffer, sizeof(gateway_buffer)) == nullptr) {
    return false;
  }

  if (route.dwForwardIfIndex == 0 || std::string(gateway_buffer) == "0.0.0.0") {
    return false;
  }

  *gateway = gateway_buffer;
  *interface_index = route.dwForwardIfIndex;
  return true;
}

bool ReadInterfaceTrafficCounters(unsigned int interface_index,
                                  uint32_t* upload_bytes,
                                  uint32_t* download_bytes) {
  MIB_IFROW row{};
  row.dwIndex = interface_index;
  if (GetIfEntry(&row) != NO_ERROR) {
    return false;
  }

  *upload_bytes = row.dwOutOctets;
  *download_bytes = row.dwInOctets;
  return true;
}
}  // namespace
#endif

struct DesktopV2rayCore::ProcessHandle {
#if defined(_WIN32)
  PROCESS_INFORMATION pi{};
#else
  pid_t pid = -1;
#endif
};

DesktopV2rayCore::DesktopV2rayCore() = default;

DesktopV2rayCore::~DesktopV2rayCore() {
  Stop();
}

void DesktopV2rayCore::ConfigureWindowsDebugLogging(
    const WindowsDebugLoggingOptions& options) {
#if !defined(_WIN32)
  (void)options;
#else
  if (options.clear_existing_logs) {
    ClearDebugLogFile(GetPluginLogPath());
    ClearDebugLogFile(GetXrayCaptureLogPath());
  }

  SetFileLoggingEnabled(options.enable_file_logging);
  SetVerboseLoggingEnabled(options.enable_verbose_logging);
  SetXrayStdIoCaptureEnabled(options.capture_xray_stdio);

  LogLine("debug logging configured: file_logging=" +
          BoolToString(options.enable_file_logging) +
          " verbose_logging=" + BoolToString(options.enable_verbose_logging) +
          " capture_xray_stdio=" + BoolToString(options.capture_xray_stdio) +
          " clear_existing_logs=" + BoolToString(options.clear_existing_logs));
#endif
}

std::string DesktopV2rayCore::BuildTempConfigPath() const {
#if defined(_WIN32)
  char temp_path[MAX_PATH];
  GetTempPathA(MAX_PATH, temp_path);
  return std::string(temp_path) + "dart_v2ray_config.json";
#else
  const char* tmp = std::getenv("TMPDIR");
  std::string base = tmp != nullptr ? tmp : "/tmp";
  return base + "/dart_v2ray_config.json";
#endif
}

bool DesktopV2rayCore::WriteConfig(const std::string& config) {
  config_path_ = BuildTempConfigPath();
  std::ofstream out(config_path_, std::ios::binary | std::ios::trunc);
  if (!out.is_open()) {
#if defined(_WIN32)
    LogLine("WriteConfig failed to open path=" + config_path_);
#endif
    return false;
  }
  out << config;
#if defined(_WIN32)
  if (!out.good()) {
    LogLine("WriteConfig failed while writing path=" + config_path_ +
            " bytes=" + std::to_string(config.size()));
  } else {
    LogLine("WriteConfig succeeded path=" + config_path_ +
            " bytes=" + std::to_string(config.size()));
  }
#endif
  return out.good();
}

DesktopV2rayCore::RuntimePaths DesktopV2rayCore::DiscoverRuntimePaths() const {
  RuntimePaths paths;
#if defined(_WIN32)
  const std::string env_xray = GetEnv("XRAY_EXECUTABLE");
  if (!env_xray.empty() && FileExists(env_xray)) {
    paths.xray_executable = env_xray;
  }

  const std::string env_wintun = GetEnv("WINTUN_DLL");
  if (!env_wintun.empty() && FileExists(env_wintun)) {
    paths.wintun_dll = env_wintun;
  }

  if (paths.xray_executable.empty()) {
    paths.xray_executable = FindBinaryFromPath("xray.exe");
  }
  if (paths.wintun_dll.empty()) {
    paths.wintun_dll = FindBinaryFromPath("wintun.dll");
  }

  const std::string executable_directory = GetExecutableDirectory();
  const std::string module_directory = GetCurrentModuleDirectory();

  const std::vector<std::string> roots = {
      executable_directory,
      module_directory,
      executable_directory.empty() ? "" : executable_directory + "\\data\\flutter_assets",
      module_directory.empty() ? "" : module_directory + "\\bin"};

  for (const auto& root : roots) {
    if (root.empty()) {
      continue;
    }

    if (paths.xray_executable.empty()) {
      const std::vector<std::string> xray_candidates = {root + "\\xray.exe", root + "\\bin\\xray.exe"};
      for (const auto& candidate : xray_candidates) {
        if (FileExists(candidate)) {
          paths.xray_executable = candidate;
          break;
        }
      }
    }

    if (paths.wintun_dll.empty()) {
      const std::vector<std::string> wintun_candidates = {root + "\\wintun.dll", root + "\\bin\\wintun.dll"};
      for (const auto& candidate : wintun_candidates) {
        if (FileExists(candidate)) {
          paths.wintun_dll = candidate;
          break;
        }
      }
    }
  }

#else
  const char* env_xray = std::getenv("XRAY_EXECUTABLE");
  if (env_xray != nullptr && std::string(env_xray).size() > 0) {
    paths.xray_executable = std::string(env_xray);
  } else {
    paths.xray_executable = "xray";
  }
#endif
  return paths;
}

std::string DesktopV2rayCore::ValidateRuntime(const RuntimePaths& paths, bool tun_requested) const {
  if (paths.xray_executable.empty()) {
#if defined(_WIN32)
    const std::string error = BuildMissingXrayError();
#else
    const std::string error =
        "xray executable could not be located. Set XRAY_EXECUTABLE or add xray to PATH.";
#endif
#if defined(_WIN32)
    LogLine("ValidateRuntime failed: " + error);
#endif
    return error;
  }
#if defined(_WIN32)
  if (tun_requested && paths.wintun_dll.empty()) {
    const std::string error =
        "wintun.dll is required for Windows TUN mode. Provide WINTUN_DLL or bundle windows/bin/wintun.dll.";
    LogLine("ValidateRuntime failed: " + error);
    return error;
  }
#endif
  return "";
}

std::string DesktopV2rayCore::Initialize() {
  runtime_paths_ = DiscoverRuntimePaths();
#if defined(_WIN32)
  LogLine("initialize: xray=" + runtime_paths_.xray_executable +
          " wintun=" + (runtime_paths_.wintun_dll.empty() ? "<not found>" : runtime_paths_.wintun_dll));
#endif
  const std::string error = ValidateRuntime(runtime_paths_, false);
#if defined(_WIN32)
  LogLine(error.empty() ? "initialize: runtime validation OK"
                        : "initialize: runtime validation FAILED: " + error);
#endif
  return error;
}

bool DesktopV2rayCore::IsElevated() const {
#if defined(_WIN32)
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }

  TOKEN_ELEVATION elevation{};
  DWORD size = 0;
  const BOOL ok = GetTokenInformation(token, TokenElevation, &elevation,
                                      sizeof(elevation), &size);
  CloseHandle(token);
  return ok == TRUE && elevation.TokenIsElevated != 0;
#else
  return true;
#endif
}

std::string DesktopV2rayCore::BuildEffectiveConfig(const std::string& base_config,
                                                   const StartOptions& options,
                                                   bool* use_tun,
                                                   std::string* mode_note) const {
  *use_tun = false;
  *mode_note = "proxy";

#if defined(_WIN32)
  if (options.proxy_only) {
    return base_config;
  }

  if (!IsElevated()) {
    *mode_note = "proxy_fallback_not_elevated";
    if (options.require_tun) {
      return "";
    }
    return base_config;
  }

  if (runtime_paths_.wintun_dll.empty()) {
    *mode_note = "proxy_fallback_missing_wintun";
    if (options.require_tun) {
      return "";
    }
    return base_config;
  }

  std::string tuned = base_config;
  if (!InsertTunInbound(&tuned, options.dns_servers)) {
    *mode_note = "proxy_fallback_invalid_config";
    if (options.require_tun) {
      return "";
    }
    return base_config;
  }

  if (!InjectDnsServers(&tuned, options.dns_servers)) {
    *mode_note = "proxy_fallback_invalid_dns";
    if (options.require_tun) {
      return "";
    }
    return base_config;
  }

  if (FindPreferredOutboundTag(tuned).empty()) {
    *mode_note = "proxy_fallback_missing_outbound_tag";
    if (options.require_tun) {
      return "";
    }
    return base_config;
  }

  if (!InjectTunRouting(&tuned)) {
    *mode_note = "proxy_fallback_invalid_routing";
    if (options.require_tun) {
      return "";
    }
    return base_config;
  }

  *use_tun = true;
  *mode_note = "tun";
  if (IsVerboseLoggingEnabled()) {
    LogLine("effective_config=" + tuned);
  } else {
    LogLine("effective_config prepared for TUN (bytes=" + std::to_string(tuned.size()) + ")");
  }
  return tuned;
#else
  (void)options;
  return base_config;
#endif
}

std::string DesktopV2rayCore::Start(const std::string& config, const StartOptions& options) {
#if defined(_WIN32)
  LogLine("Start requested: config_bytes=" + std::to_string(config.size()) +
          " proxy_only=" + BoolToString(options.proxy_only) +
          " require_tun=" + BoolToString(options.require_tun) +
          " bypass_subnets=" + std::to_string(options.bypass_subnets.size()) +
          " dns_servers=" + std::to_string(options.dns_servers.size()) +
          " auto_disconnect_seconds=" +
          (options.auto_disconnect_seconds.has_value()
               ? std::to_string(*options.auto_disconnect_seconds)
               : "none"));
#endif
  Stop();

  runtime_paths_ = DiscoverRuntimePaths();

  const bool tun_requested = !options.proxy_only;
  const std::string runtime_error = ValidateRuntime(runtime_paths_, tun_requested && options.require_tun);
  if (!runtime_error.empty()) {
#if defined(_WIN32)
    LogLine("Start aborted due to runtime validation error: " + runtime_error);
#endif
    return runtime_error;
  }

  bool has_usable_outbounds = false;
#if defined(_WIN32)
  has_usable_outbounds = HasUsableOutbounds(config);
#else
  const size_t outbounds_pos = config.find("\"outbounds\"");
  if (outbounds_pos != std::string::npos) {
    const size_t array_start = config.find('[', outbounds_pos);
    if (array_start != std::string::npos) {
      const size_t array_end = config.find(']', array_start);
      has_usable_outbounds =
          array_end != std::string::npos && config.find('{', array_start) != std::string::npos;
    }
  }
#endif

  if (!has_usable_outbounds) {
#if defined(_WIN32)
    LogLine("Start aborted: provided config does not contain any usable outbounds.");
#endif
    return "Provided Xray config must contain at least one outbound.";
  }

  bool use_tun = false;
  std::string mode_note;
  const std::string effective_config = BuildEffectiveConfig(config, options, &use_tun, &mode_note);

  if (effective_config.empty()) {
    if (mode_note == "proxy_fallback_not_elevated") {
#if defined(_WIN32)
      LogLine("Start failed: Windows TUN mode requested without elevation.");
#endif
      return "Windows TUN mode requires administrator privileges. Restart app as Administrator or set proxyOnly=true.";
    }
    if (mode_note == "proxy_fallback_missing_wintun") {
#if defined(_WIN32)
      LogLine("Start failed: Windows TUN mode requested but wintun.dll was not found.");
#endif
      return "Windows TUN mode requested but wintun.dll was not found.";
    }
    if (mode_note == "proxy_fallback_missing_outbound_tag") {
#if defined(_WIN32)
      LogLine("Start failed: Windows TUN mode requires at least one outbound tag.");
#endif
      return "Windows TUN mode requires at least one outbound with a tag. Use tag \"proxy\" or any tagged outbound.";
    }
#if defined(_WIN32)
    LogLine("Start failed: unable to construct TUN config. mode_note=" + mode_note);
#endif
    return "Failed to construct TUN config from provided JSON. Set proxyOnly=true or provide a standard Xray config root object.";
  }

  if (!WriteConfig(effective_config)) {
    return "Cannot write temporary Xray configuration file.";
  }

  {
    std::lock_guard<std::mutex> lock(mutex_);
    state_ = "CONNECTING";
    transport_mode_ = use_tun ? "tun" : "proxy";
  }

#if defined(_WIN32)
  std::ostringstream command;
  command << '"' << runtime_paths_.xray_executable << '"' << " run -c \"" << config_path_ << "\"";
  std::string command_string = command.str();

  STARTUPINFOA si{};
  si.cb = sizeof(STARTUPINFOA);
  auto process = std::make_unique<ProcessHandle>();

  // Redirect xray stdout/stderr only when explicitly enabled to avoid
  // excessive disk I/O in production.
  const bool capture_xray_stdio = use_tun && IsXrayStdIoCaptureEnabled();
  HANDLE xray_log_handle = INVALID_HANDLE_VALUE;
  if (capture_xray_stdio) {
    const std::string xray_log_path = GetXrayCaptureLogPath();
    if (!xray_log_path.empty()) {
      SECURITY_ATTRIBUTES sa{};
      sa.nLength = sizeof(SECURITY_ATTRIBUTES);
      sa.bInheritHandle = TRUE;
      xray_log_handle = CreateFileA(xray_log_path.c_str(), FILE_APPEND_DATA,
                                    FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (xray_log_handle != INVALID_HANDLE_VALUE) {
        si.hStdOutput = xray_log_handle;
        si.hStdError = xray_log_handle;
        si.dwFlags |= STARTF_USESTDHANDLES;
        LogLine("xray stdio capture enabled: " + xray_log_path);
      }
    }
  } else if (use_tun) {
    LogLine("xray stdio capture disabled (set DART_V2RAY_WINDOWS_CAPTURE_XRAY_IO=1 to enable).");
  }

  // For TUN mode, ensure wintun.dll is next to xray.exe so xray finds it
  // without needing a custom environment block (which breaks wintun driver install).
  std::string copied_wintun_path;
  if (use_tun && !runtime_paths_.wintun_dll.empty()) {
    std::string xray_dir = runtime_paths_.xray_executable.substr(0, runtime_paths_.xray_executable.find_last_of("\\/"));
    std::string wintun_name = runtime_paths_.wintun_dll.substr(runtime_paths_.wintun_dll.find_last_of("\\/") + 1);
    std::string target_wintun = xray_dir + "\\" + wintun_name;
    if (target_wintun != runtime_paths_.wintun_dll) {
      if (CopyFileA(runtime_paths_.wintun_dll.c_str(), target_wintun.c_str(), FALSE)) {
        copied_wintun_path = target_wintun;
        LogLine("TUN: copied wintun.dll to xray directory: " + copied_wintun_path);
      } else {
        LogLine("TUN: failed to copy wintun.dll to xray directory, win32_error=" +
                std::to_string(GetLastError()));
      }
    }
    LogLine("TUN: wintun_dll=" + runtime_paths_.wintun_dll + " command=" + command_string);
  } else {
    LogLine("TUN: no wintun copy needed. use_tun=" + std::string(use_tun ? "true" : "false") +
            " wintun_dll=" + (runtime_paths_.wintun_dll.empty() ? "<empty>" : runtime_paths_.wintun_dll));
  }

  LogLine("CreateProcessA: " + command_string);
  if (!CreateProcessA(nullptr, command_string.data(), nullptr, nullptr, TRUE,
                      CREATE_NO_WINDOW,
                      nullptr,
                      nullptr, &si, &process->pi)) {
    if (xray_log_handle != INVALID_HANDLE_VALUE) {
      CloseHandle(xray_log_handle);
    }
    const DWORD error_code = GetLastError();
    std::lock_guard<std::mutex> lock(mutex_);
    state_ = "DISCONNECTED";
    std::ostringstream error;
    error << "Unable to start xray process. Ensure xray.exe is bundled or XRAY_EXECUTABLE is set."
          << " executable=" << runtime_paths_.xray_executable << " config=" << config_path_
          << " win32_error=" << error_code << " (" << Win32ErrorToString(error_code)
          << ")";
    return error.str();
  }

  if (xray_log_handle != INVALID_HANDLE_VALUE) {
    CloseHandle(xray_log_handle);
  }
  process_ = std::move(process);
#else
  pid_t pid = fork();
  if (pid == 0) {
    execlp(runtime_paths_.xray_executable.c_str(), runtime_paths_.xray_executable.c_str(), "run",
           "-c", config_path_.c_str(), static_cast<char*>(nullptr));
    _exit(1);
  }
  if (pid < 0) {
    std::lock_guard<std::mutex> lock(mutex_);
    state_ = "DISCONNECTED";
    return "Unable to fork xray process.";
  }

  auto process = std::make_unique<ProcessHandle>();
  process->pid = pid;
  process_ = std::move(process);
#endif

#if defined(_WIN32)
  if (use_tun) {
    std::string network_error;
    if (!ApplyTunNetworking(options, effective_config, &network_error)) {
      Stop();
      if (options.require_tun) {
        return network_error;
      }
      LogLine("TUN networking failed; switching to proxy fallback: " + network_error);
      StartOptions fallback = options;
      fallback.proxy_only = true;
      return Start(config, fallback);
    }
  }
#endif

  bool should_start_auto_disconnect_timer = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    state_ = "CONNECTED";
    connected_at_ = std::chrono::steady_clock::now();
    auto_disconnected_ = false;
    auto_disconnect_timestamp_ms_ = 0;
#if defined(_WIN32)
    if (!use_tun) {
      tun_interface_index_.reset();
      upstream_interface_index_.reset();
    }
#endif
    has_traffic_sample_ = false;
    last_upload_counter_sample_ = 0;
    last_download_counter_sample_ = 0;
    accumulated_upload_bytes_ = 0;
    accumulated_download_bytes_ = 0;
    last_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
    has_process_traffic_sample_ = false;
    last_process_upload_counter_sample_ = 0;
    last_process_download_counter_sample_ = 0;
    accumulated_process_upload_bytes_ = 0;
    accumulated_process_download_bytes_ = 0;
    last_process_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
    has_upstream_traffic_sample_ = false;
    last_upstream_upload_counter_sample_ = 0;
    last_upstream_download_counter_sample_ = 0;
    accumulated_upstream_upload_bytes_ = 0;
    accumulated_upstream_download_bytes_ = 0;
    last_upstream_traffic_sample_at_ = std::chrono::steady_clock::time_point{};

    if (options.auto_disconnect_seconds.has_value() && options.auto_disconnect_seconds.value() > 0) {
      auto_disconnect_deadline_ = connected_at_ + std::chrono::seconds(*options.auto_disconnect_seconds);
      should_start_auto_disconnect_timer = true;
    } else {
      auto_disconnect_deadline_.reset();
    }
  }

  if (should_start_auto_disconnect_timer) {
    StartAutoDisconnectTimer();
  } else {
    StopAutoDisconnectTimer();
  }

#if defined(_WIN32)
  LogLine("started in mode=" + transport_mode_ + " note=" + mode_note + " config=" + config_path_);
#endif

  return "";
}

std::string DesktopV2rayCore::Stop(bool from_auto_disconnect) {
#if defined(_WIN32)
  LogLine("Stop requested: from_auto_disconnect=" + BoolToString(from_auto_disconnect));
#endif
  bool has_process = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    has_process = process_ != nullptr;
    if (!has_process) {
      state_ = "DISCONNECTED";
      transport_mode_ = "idle";
      auto_disconnect_deadline_.reset();
#if defined(_WIN32)
      tun_interface_index_.reset();
      upstream_interface_index_.reset();
#endif
      has_traffic_sample_ = false;
      last_upload_counter_sample_ = 0;
      last_download_counter_sample_ = 0;
      accumulated_upload_bytes_ = 0;
      accumulated_download_bytes_ = 0;
      last_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
      has_process_traffic_sample_ = false;
      last_process_upload_counter_sample_ = 0;
      last_process_download_counter_sample_ = 0;
      accumulated_process_upload_bytes_ = 0;
      accumulated_process_download_bytes_ = 0;
      last_process_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
      has_upstream_traffic_sample_ = false;
      last_upstream_upload_counter_sample_ = 0;
      last_upstream_download_counter_sample_ = 0;
      accumulated_upstream_upload_bytes_ = 0;
      accumulated_upstream_download_bytes_ = 0;
      last_upstream_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
    }
  }

  if (!has_process) {
    StopAutoDisconnectTimer();
#if defined(_WIN32)
    LogLine("Stop completed: no active xray process.");
#endif
    return "";
  }

#if defined(_WIN32)
  CleanupTunNetworking();
  TerminateProcess(process_->pi.hProcess, 0);
  WaitForSingleObject(process_->pi.hProcess, 3000);
  CloseHandle(process_->pi.hProcess);
  CloseHandle(process_->pi.hThread);
#else
  kill(process_->pid, SIGTERM);
#endif

  process_.reset();

  if (!config_path_.empty()) {
#if defined(_WIN32)
    DeleteFileA(config_path_.c_str());
#else
    std::error_code ec;
    std::filesystem::remove(config_path_, ec);
#endif
  }

  {
    std::lock_guard<std::mutex> lock(mutex_);
    state_ = "DISCONNECTED";
    transport_mode_ = "idle";
    if (from_auto_disconnect) {
      auto_disconnected_ = true;
      auto_disconnect_timestamp_ms_ = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::system_clock::now().time_since_epoch())
          .count();
    }
    auto_disconnect_deadline_.reset();
#if defined(_WIN32)
    tun_interface_index_.reset();
    upstream_interface_index_.reset();
#endif
    has_traffic_sample_ = false;
    last_upload_counter_sample_ = 0;
    last_download_counter_sample_ = 0;
    accumulated_upload_bytes_ = 0;
    accumulated_download_bytes_ = 0;
    last_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
    has_process_traffic_sample_ = false;
    last_process_upload_counter_sample_ = 0;
    last_process_download_counter_sample_ = 0;
    accumulated_process_upload_bytes_ = 0;
    accumulated_process_download_bytes_ = 0;
    last_process_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
    has_upstream_traffic_sample_ = false;
    last_upstream_upload_counter_sample_ = 0;
    last_upstream_download_counter_sample_ = 0;
    accumulated_upstream_upload_bytes_ = 0;
    accumulated_upstream_download_bytes_ = 0;
    last_upstream_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
  }

  StopAutoDisconnectTimer();

#if defined(_WIN32)
  LogLine("Stop completed successfully.");
#endif
  return "";
}

std::string DesktopV2rayCore::GetCoreVersion() {
  runtime_paths_ = DiscoverRuntimePaths();
  if (runtime_paths_.xray_executable.empty()) {
#if defined(_WIN32)
    LogLine("GetCoreVersion: xray executable unavailable.");
#endif
    return "xray-unavailable";
  }
#if defined(_WIN32)
  std::ostringstream command;
  command << '"' << runtime_paths_.xray_executable << '"' << " version";
  FILE* pipe = _popen(command.str().c_str(), "r");
#else
  std::string command = runtime_paths_.xray_executable + " version";
  FILE* pipe = popen(command.c_str(), "r");
#endif

  if (!pipe) {
#if defined(_WIN32)
    LogLine("GetCoreVersion: failed to spawn version command.");
#endif
    return "xray-unavailable";
  }

  char buffer[256];
  std::string output;
  while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
    output += buffer;
  }

#if defined(_WIN32)
  _pclose(pipe);
#else
  pclose(pipe);
#endif

  if (output.empty()) {
#if defined(_WIN32)
    LogLine("GetCoreVersion: command returned no output.");
#endif
    return "xray-unavailable";
  }

  auto newline = output.find('\n');
  if (newline != std::string::npos) {
    output = output.substr(0, newline);
  }
#if defined(_WIN32)
  LogLine("GetCoreVersion: " + output);
#endif
  return output;
}

int DesktopV2rayCore::GetServerDelay(const std::string& url) const {
  const int delay = MeasureTcpDelay(url);
#if defined(_WIN32)
  LogLine("GetServerDelay url=" + url + " delay_ms=" + std::to_string(delay));
#endif
  return delay;
}

int DesktopV2rayCore::GetConnectedServerDelay(const std::string& url) const {
  std::lock_guard<std::mutex> lock(mutex_);
  if (state_ != "CONNECTED") {
#if defined(_WIN32)
    LogLine("GetConnectedServerDelay rejected because state=" + state_);
#endif
    return -1;
  }
  const int delay = MeasureTcpDelay(url);
#if defined(_WIN32)
  LogLine("GetConnectedServerDelay url=" + url + " delay_ms=" + std::to_string(delay));
#endif
  return delay;
}

bool DesktopV2rayCore::IsProcessRunning() const {
#if defined(_WIN32)
  if (!process_) {
    return false;
  }
  DWORD exit_code = STILL_ACTIVE;
  if (!GetExitCodeProcess(process_->pi.hProcess, &exit_code)) {
    return false;
  }
  return exit_code == STILL_ACTIVE;
#else
  return process_ != nullptr;
#endif
}

void DesktopV2rayCore::PollProcessAndHandleExit() {
  bool should_cleanup = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!process_ || state_ == "DISCONNECTED") {
      return;
    }
    if (IsProcessRunning()) {
      return;
    }
    should_cleanup = true;
  }

  if (!should_cleanup) {
    return;
  }
  Stop();
}

int DesktopV2rayCore::UpdateAutoDisconnectTime(int additional_seconds) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!auto_disconnect_deadline_.has_value()) {
    return -1;
  }

  auto_disconnect_deadline_ = auto_disconnect_deadline_.value() +
                              std::chrono::seconds(additional_seconds);
  timer_cv_.notify_all();

  auto now = std::chrono::steady_clock::now();
  if (now >= auto_disconnect_deadline_.value()) {
    return 0;
  }

  return static_cast<int>(
      std::chrono::duration_cast<std::chrono::seconds>(auto_disconnect_deadline_.value() - now)
          .count());
}

int DesktopV2rayCore::GetRemainingAutoDisconnectTime() const {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!auto_disconnect_deadline_.has_value()) {
    return -1;
  }

  auto now = std::chrono::steady_clock::now();
  if (now >= auto_disconnect_deadline_.value()) {
    return 0;
  }

  return static_cast<int>(
      std::chrono::duration_cast<std::chrono::seconds>(auto_disconnect_deadline_.value() - now)
          .count());
}

void DesktopV2rayCore::CancelAutoDisconnect() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    auto_disconnect_deadline_.reset();
  }
  StopAutoDisconnectTimer();
}

bool DesktopV2rayCore::WasAutoDisconnected() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return auto_disconnected_;
}

void DesktopV2rayCore::ClearAutoDisconnectFlag() {
  std::lock_guard<std::mutex> lock(mutex_);
  auto_disconnected_ = false;
  auto_disconnect_timestamp_ms_ = 0;
}

int64_t DesktopV2rayCore::GetAutoDisconnectTimestamp() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return auto_disconnect_timestamp_ms_;
}

std::vector<std::string> DesktopV2rayCore::BuildStatusPayload() const {
  std::lock_guard<std::mutex> lock(mutex_);

  int duration = 0;
  if (state_ == "CONNECTED") {
    duration = static_cast<int>(
        std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() -
                                                          connected_at_)
            .count());
  }

  uint64_t upload_speed = 0;
  uint64_t download_speed = 0;
  uint64_t upload_total = 0;
  uint64_t download_total = 0;
  std::string effective_state = state_;
  if (effective_state == "DISCONNECTED" && auto_disconnected_) {
    effective_state = "AUTO_DISCONNECTED";
  }
  bool process_running = IsProcessRunning();

#if defined(_WIN32)
  std::string selected_source = "none";
  std::string selected_reason = state_ == "CONNECTED" ? "no_data" : "not_connected";
  bool tun_counter_read_ok = false;
  bool process_counter_read_ok = false;
  bool upstream_counter_read_ok = false;
  bool had_tun_sample_before_read = false;
  bool had_process_sample_before_read = false;
  bool had_upstream_sample_before_read = false;
  uint32_t tun_upload_raw = 0;
  uint32_t tun_download_raw = 0;
  uint64_t process_upload_raw = 0;
  uint64_t process_download_raw = 0;
  uint32_t upstream_upload_raw = 0;
  uint32_t upstream_download_raw = 0;

  if (state_ == "CONNECTED" && transport_mode_ == "tun" && tun_interface_index_.has_value()) {
    uint32_t current_upload = 0;
    uint32_t current_download = 0;
    if (ReadInterfaceTrafficCounters(*tun_interface_index_, &current_upload, &current_download)) {
      tun_counter_read_ok = true;
      tun_upload_raw = current_upload;
      tun_download_raw = current_download;
      had_tun_sample_before_read = has_traffic_sample_;
      const auto now = std::chrono::steady_clock::now();
      if (has_traffic_sample_) {
        const double elapsed_seconds =
            std::chrono::duration<double>(now - last_traffic_sample_at_).count();
        const uint64_t kCounterWindow = static_cast<uint64_t>(std::numeric_limits<uint32_t>::max()) + 1ULL;
        const uint64_t delta_upload =
            current_upload >= last_upload_counter_sample_
                ? static_cast<uint64_t>(current_upload - last_upload_counter_sample_)
                : kCounterWindow - static_cast<uint64_t>(last_upload_counter_sample_) +
                      static_cast<uint64_t>(current_upload);
        const uint64_t delta_download =
            current_download >= last_download_counter_sample_
                ? static_cast<uint64_t>(current_download - last_download_counter_sample_)
                : kCounterWindow - static_cast<uint64_t>(last_download_counter_sample_) +
                      static_cast<uint64_t>(current_download);

        accumulated_upload_bytes_ += delta_upload;
        accumulated_download_bytes_ += delta_download;

        if (elapsed_seconds > 0.0) {
          upload_speed = static_cast<uint64_t>(delta_upload / elapsed_seconds);
          download_speed = static_cast<uint64_t>(delta_download / elapsed_seconds);
        }
      }

      last_upload_counter_sample_ = current_upload;
      last_download_counter_sample_ = current_download;
      last_traffic_sample_at_ = now;
      has_traffic_sample_ = true;
      upload_total = accumulated_upload_bytes_;
      download_total = accumulated_download_bytes_;
      selected_reason = had_tun_sample_before_read ? "tun_sample_ready" : "tun_first_sample";
    } else {
      has_traffic_sample_ = false;
      last_upload_counter_sample_ = 0;
      last_download_counter_sample_ = 0;
      accumulated_upload_bytes_ = 0;
      accumulated_download_bytes_ = 0;
      last_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
      selected_reason = "tun_counter_read_failed";
    }
  } else if (state_ == "CONNECTED" && transport_mode_ == "tun" &&
             !tun_interface_index_.has_value()) {
    selected_reason = "tun_interface_index_missing";
  }

  uint64_t process_upload_speed = 0;
  uint64_t process_download_speed = 0;
  uint64_t process_upload_total = 0;
  uint64_t process_download_total = 0;
  if (state_ == "CONNECTED" && process_ != nullptr) {
    IO_COUNTERS io_counters{};
    if (GetProcessIoCounters(process_->pi.hProcess, &io_counters) == TRUE) {
      process_counter_read_ok = true;
      const uint64_t current_process_upload = io_counters.WriteTransferCount;
      const uint64_t current_process_download = io_counters.ReadTransferCount;
      process_upload_raw = current_process_upload;
      process_download_raw = current_process_download;
      had_process_sample_before_read = has_process_traffic_sample_;
      const auto now = std::chrono::steady_clock::now();

      if (has_process_traffic_sample_) {
        const double elapsed_seconds =
            std::chrono::duration<double>(now - last_process_traffic_sample_at_).count();
        const uint64_t delta_upload =
            current_process_upload >= last_process_upload_counter_sample_
                ? current_process_upload - last_process_upload_counter_sample_
                : 0;
        const uint64_t delta_download =
            current_process_download >= last_process_download_counter_sample_
                ? current_process_download - last_process_download_counter_sample_
                : 0;

        accumulated_process_upload_bytes_ += delta_upload;
        accumulated_process_download_bytes_ += delta_download;

        if (elapsed_seconds > 0.0) {
          process_upload_speed = static_cast<uint64_t>(delta_upload / elapsed_seconds);
          process_download_speed = static_cast<uint64_t>(delta_download / elapsed_seconds);
        }
      }

      last_process_upload_counter_sample_ = current_process_upload;
      last_process_download_counter_sample_ = current_process_download;
      last_process_traffic_sample_at_ = now;
      has_process_traffic_sample_ = true;
      process_upload_total = accumulated_process_upload_bytes_;
      process_download_total = accumulated_process_download_bytes_;
    } else {
      has_process_traffic_sample_ = false;
      last_process_upload_counter_sample_ = 0;
      last_process_download_counter_sample_ = 0;
      accumulated_process_upload_bytes_ = 0;
      accumulated_process_download_bytes_ = 0;
      last_process_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
      if (selected_reason == "no_data") {
        selected_reason = "process_counter_read_failed";
      }
    }
  } else if (state_ == "CONNECTED" && process_ == nullptr && selected_reason == "no_data") {
    selected_reason = "process_handle_missing";
  }

  const bool interface_has_data =
      upload_speed > 0 || download_speed > 0 || upload_total > 0 || download_total > 0;
  const bool process_has_data = process_upload_speed > 0 || process_download_speed > 0 ||
                                process_upload_total > 0 || process_download_total > 0;
  if (interface_has_data) {
    selected_source = "tun_interface";
    selected_reason = "tun_interface_data";
  }

  if (!interface_has_data && process_has_data) {
    upload_speed = process_upload_speed;
    download_speed = process_download_speed;
    upload_total = process_upload_total;
    download_total = process_download_total;
    selected_source = "process_io";
    selected_reason = "process_io_fallback";
  }

  const bool still_no_data =
      upload_speed == 0 && download_speed == 0 && upload_total == 0 && download_total == 0;
  if (still_no_data && state_ == "CONNECTED" && transport_mode_ == "tun" &&
      upstream_interface_index_.has_value()) {
    uint32_t current_upstream_upload = 0;
    uint32_t current_upstream_download = 0;
    if (ReadInterfaceTrafficCounters(*upstream_interface_index_, &current_upstream_upload,
                                     &current_upstream_download)) {
      upstream_counter_read_ok = true;
      upstream_upload_raw = current_upstream_upload;
      upstream_download_raw = current_upstream_download;
      had_upstream_sample_before_read = has_upstream_traffic_sample_;
      const auto now = std::chrono::steady_clock::now();
      if (has_upstream_traffic_sample_) {
        const double elapsed_seconds =
            std::chrono::duration<double>(now - last_upstream_traffic_sample_at_).count();
        const uint64_t kCounterWindow =
            static_cast<uint64_t>(std::numeric_limits<uint32_t>::max()) + 1ULL;
        const uint64_t delta_upload =
            current_upstream_upload >= last_upstream_upload_counter_sample_
                ? static_cast<uint64_t>(current_upstream_upload - last_upstream_upload_counter_sample_)
                : kCounterWindow - static_cast<uint64_t>(last_upstream_upload_counter_sample_) +
                      static_cast<uint64_t>(current_upstream_upload);
        const uint64_t delta_download =
            current_upstream_download >= last_upstream_download_counter_sample_
                ? static_cast<uint64_t>(current_upstream_download - last_upstream_download_counter_sample_)
                : kCounterWindow - static_cast<uint64_t>(last_upstream_download_counter_sample_) +
                      static_cast<uint64_t>(current_upstream_download);

        accumulated_upstream_upload_bytes_ += delta_upload;
        accumulated_upstream_download_bytes_ += delta_download;

        if (elapsed_seconds > 0.0) {
          upload_speed = static_cast<uint64_t>(delta_upload / elapsed_seconds);
          download_speed = static_cast<uint64_t>(delta_download / elapsed_seconds);
        }
      }

      last_upstream_upload_counter_sample_ = current_upstream_upload;
      last_upstream_download_counter_sample_ = current_upstream_download;
      last_upstream_traffic_sample_at_ = now;
      has_upstream_traffic_sample_ = true;
      upload_total = accumulated_upstream_upload_bytes_;
      download_total = accumulated_upstream_download_bytes_;
      const bool upstream_has_data =
          upload_speed > 0 || download_speed > 0 || upload_total > 0 || download_total > 0;
      if (upstream_has_data) {
        selected_source = "upstream_interface";
        selected_reason = "upstream_interface_fallback";
      } else if (selected_reason == "no_data") {
        selected_reason =
            had_upstream_sample_before_read ? "upstream_no_delta_yet" : "upstream_first_sample";
      }
    } else {
      has_upstream_traffic_sample_ = false;
      last_upstream_upload_counter_sample_ = 0;
      last_upstream_download_counter_sample_ = 0;
      accumulated_upstream_upload_bytes_ = 0;
      accumulated_upstream_download_bytes_ = 0;
      last_upstream_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
      if (selected_reason == "no_data") {
        selected_reason = "upstream_counter_read_failed";
      }
    }
  } else if (still_no_data && state_ == "CONNECTED" && transport_mode_ == "tun" &&
             !upstream_interface_index_.has_value() && selected_reason == "no_data") {
    selected_reason = "upstream_interface_index_missing";
  }

  if (state_ == "CONNECTED" && selected_source == "none") {
    if (transport_mode_ == "proxy") {
      if (process_counter_read_ok) {
        selected_reason =
            had_process_sample_before_read ? "proxy_no_delta_yet" : "proxy_first_sample";
      } else if (process_ == nullptr) {
        selected_reason = "proxy_process_missing";
      } else {
        selected_reason = "proxy_process_counter_unavailable";
      }
    } else if (transport_mode_ == "tun") {
      if (tun_counter_read_ok) {
        selected_reason = had_tun_sample_before_read ? "tun_no_delta_yet" : "tun_first_sample";
      } else if (!tun_interface_index_.has_value()) {
        selected_reason = "tun_interface_index_missing";
      }
    }
  }

  last_traffic_source_ = selected_source;
  last_traffic_reason_ = selected_reason;
  last_tun_counter_read_ok_ = tun_counter_read_ok;
  last_process_counter_read_ok_ = process_counter_read_ok;
  last_upstream_counter_read_ok_ = upstream_counter_read_ok;
  last_tun_upload_counter_raw_ = tun_upload_raw;
  last_tun_download_counter_raw_ = tun_download_raw;
  last_process_upload_counter_raw_ = process_upload_raw;
  last_process_download_counter_raw_ = process_download_raw;
  last_upstream_upload_counter_raw_ = upstream_upload_raw;
  last_upstream_download_counter_raw_ = upstream_download_raw;
#endif

  const bool traffic_observed =
      upload_speed > 0 || download_speed > 0 || upload_total > 0 || download_total > 0;
  bool has_any_sample = process_running;
#if defined(_WIN32)
  has_any_sample = has_traffic_sample_ || has_process_traffic_sample_ || has_upstream_traffic_sample_;
#endif

  std::string connection_phase;
  if (effective_state == "CONNECTING") {
    connection_phase = "CONNECTING";
  } else if (effective_state == "AUTO_DISCONNECTED") {
    connection_phase = "AUTO_DISCONNECTED";
  } else if (effective_state != "CONNECTED") {
    connection_phase = "DISCONNECTED";
  } else if (!process_running || !has_any_sample) {
    connection_phase = "VERIFYING";
  } else if (traffic_observed) {
    connection_phase = "ACTIVE";
  } else {
    connection_phase = "READY";
  }

  std::vector<std::string> payload = {
      std::to_string(duration),
      std::to_string(upload_speed),
      std::to_string(download_speed),
      std::to_string(upload_total),
      std::to_string(download_total),
      effective_state};

  if (auto_disconnect_deadline_.has_value()) {
    auto now = std::chrono::steady_clock::now();
    const int remaining = now >= auto_disconnect_deadline_.value()
                              ? 0
                              : static_cast<int>(
                                    std::chrono::duration_cast<std::chrono::seconds>(
                                        auto_disconnect_deadline_.value() - now)
                                        .count());
    payload.push_back(std::to_string(remaining));
  } else {
    payload.push_back("");
  }

  payload.push_back(connection_phase);
  payload.push_back(transport_mode_);
#if defined(_WIN32)
  payload.push_back(last_traffic_source_);
  payload.push_back(last_traffic_reason_);
#else
  payload.push_back("");
  payload.push_back("");
#endif
  payload.push_back(process_running ? "true" : "false");

  return payload;
}

std::map<std::string, std::string> DesktopV2rayCore::GetWindowsTrafficDebugInfo() const {
#if !defined(_WIN32)
  return {{"supported", "false"}, {"reason", "windows_only"}};
#else
  const std::vector<std::string> payload = BuildStatusPayload();
  std::lock_guard<std::mutex> lock(mutex_);

  std::map<std::string, std::string> info;
  info["supported"] = "true";
  info["state"] = payload.size() > 5 ? payload[5] : state_;
  info["connection_phase"] = payload.size() > 7 ? payload[7] : "";
  info["transport_mode"] = payload.size() > 8 ? payload[8] : transport_mode_;
  info["traffic_source"] = payload.size() > 9 ? payload[9] : last_traffic_source_;
  info["traffic_reason"] = payload.size() > 10 ? payload[10] : last_traffic_reason_;
  info["duration_seconds"] = payload.size() > 0 ? payload[0] : "0";
  info["upload_speed_bps"] = payload.size() > 1 ? payload[1] : "0";
  info["download_speed_bps"] = payload.size() > 2 ? payload[2] : "0";
  info["upload_total_bytes"] = payload.size() > 3 ? payload[3] : "0";
  info["download_total_bytes"] = payload.size() > 4 ? payload[4] : "0";
  info["remaining_auto_disconnect_seconds"] = payload.size() > 6 ? payload[6] : "";

  info["xray_process_present"] = process_ != nullptr ? "true" : "false";
  std::string process_running = "false";
  std::string process_exit_code = "none";
  if (process_ != nullptr) {
    DWORD exit_code = STILL_ACTIVE;
    if (GetExitCodeProcess(process_->pi.hProcess, &exit_code) == TRUE) {
      process_running = exit_code == STILL_ACTIVE ? "true" : "false";
      process_exit_code = std::to_string(exit_code);
    } else {
      process_exit_code = "unknown";
    }
  }
  info["xray_process_running"] = payload.size() > 11 ? payload[11] : process_running;
  info["xray_process_exit_code"] = process_exit_code;

  info["tun_interface_index"] =
      tun_interface_index_.has_value() ? std::to_string(*tun_interface_index_) : "";
  info["upstream_interface_index"] =
      upstream_interface_index_.has_value() ? std::to_string(*upstream_interface_index_) : "";

  info["tun_counter_read_ok"] = last_tun_counter_read_ok_ ? "true" : "false";
  info["tun_has_sample"] = has_traffic_sample_ ? "true" : "false";
  info["tun_upload_counter_raw"] = std::to_string(last_tun_upload_counter_raw_);
  info["tun_download_counter_raw"] = std::to_string(last_tun_download_counter_raw_);
  info["tun_upload_accumulated_bytes"] = std::to_string(accumulated_upload_bytes_);
  info["tun_download_accumulated_bytes"] = std::to_string(accumulated_download_bytes_);

  info["process_counter_read_ok"] = last_process_counter_read_ok_ ? "true" : "false";
  info["process_has_sample"] = has_process_traffic_sample_ ? "true" : "false";
  info["process_upload_counter_raw"] = std::to_string(last_process_upload_counter_raw_);
  info["process_download_counter_raw"] = std::to_string(last_process_download_counter_raw_);
  info["process_upload_accumulated_bytes"] = std::to_string(accumulated_process_upload_bytes_);
  info["process_download_accumulated_bytes"] =
      std::to_string(accumulated_process_download_bytes_);

  info["upstream_counter_read_ok"] = last_upstream_counter_read_ok_ ? "true" : "false";
  info["upstream_has_sample"] = has_upstream_traffic_sample_ ? "true" : "false";
  info["upstream_upload_counter_raw"] = std::to_string(last_upstream_upload_counter_raw_);
  info["upstream_download_counter_raw"] = std::to_string(last_upstream_download_counter_raw_);
  info["upstream_upload_accumulated_bytes"] = std::to_string(accumulated_upstream_upload_bytes_);
  info["upstream_download_accumulated_bytes"] =
      std::to_string(accumulated_upstream_download_bytes_);
  info["file_logging_enabled"] = BoolToString(IsFileLoggingEnabled());
  info["verbose_logging_enabled"] = BoolToString(IsVerboseLoggingEnabled());
  info["capture_xray_io_enabled"] = BoolToString(IsXrayStdIoCaptureEnabled());
  info["plugin_log_path"] = GetPluginLogPath();
  info["plugin_log_exists"] = BoolToString(FileExists(GetPluginLogPath()));
  info["xray_log_path"] = GetXrayCaptureLogPath();
  info["xray_log_exists"] = BoolToString(FileExists(GetXrayCaptureLogPath()));
  info["config_path"] = config_path_;
  info["xray_executable"] = runtime_paths_.xray_executable;
  info["wintun_dll"] = runtime_paths_.wintun_dll;

  return info;
#endif
}

std::map<std::string, std::string> DesktopV2rayCore::GetWindowsDebugLogs(int max_bytes) const {
#if !defined(_WIN32)
  (void)max_bytes;
  return {{"supported", "false"}, {"reason", "windows_only"}};
#else
  const int bounded_max_bytes = std::max(1024, std::min(max_bytes, 262144));
  const std::string plugin_log_path = GetPluginLogPath();
  const std::string xray_log_path = GetXrayCaptureLogPath();

  std::map<std::string, std::string> info;
  info["supported"] = "true";
  info["max_bytes"] = std::to_string(bounded_max_bytes);
  info["file_logging_enabled"] = BoolToString(IsFileLoggingEnabled());
  info["verbose_logging_enabled"] = BoolToString(IsVerboseLoggingEnabled());
  info["capture_xray_io_enabled"] = BoolToString(IsXrayStdIoCaptureEnabled());
  info["plugin_log_path"] = plugin_log_path;
  info["plugin_log_exists"] = BoolToString(FileExists(plugin_log_path));
  info["plugin_log_tail"] = ReadFileTail(plugin_log_path, static_cast<size_t>(bounded_max_bytes));
  info["xray_log_path"] = xray_log_path;
  info["xray_log_exists"] = BoolToString(FileExists(xray_log_path));
  info["xray_log_tail"] = ReadFileTail(xray_log_path, static_cast<size_t>(bounded_max_bytes));
  return info;
#endif
}

#if defined(_WIN32)
std::string DesktopV2rayCore::ExecuteSystemCommand(const std::string& command) const {
#if defined(_WIN32)
  if (IsVerboseLoggingEnabled()) {
    LogLine("ExecuteSystemCommand: " + command);
  }
#endif
  std::ostringstream wrapped;
  wrapped << "cmd /C \"" << command << "\"";
  FILE* pipe = _popen(wrapped.str().c_str(), "r");
  if (!pipe) {
#if defined(_WIN32)
    LogLine("ExecuteSystemCommand failed to spawn shell for command: " + command);
#endif
    return "Failed to invoke command shell.";
  }

  char buffer[256];
  std::string output;
  while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
    output += buffer;
  }
  const int exit_code = _pclose(pipe);
  if (exit_code != 0) {
    std::ostringstream error;
    error << "command failed (" << exit_code << "): " << command << " output=" << output;
#if defined(_WIN32)
    LogLine("ExecuteSystemCommand failed: " + error.str());
#endif
    return error.str();
  }
#if defined(_WIN32)
  if (IsVerboseLoggingEnabled()) {
    LogLine("ExecuteSystemCommand succeeded: " + command);
  }
#endif
  return "";
}

bool DesktopV2rayCore::ApplyTunNetworking(const StartOptions& options,
                                          const std::string& effective_config,
                                          std::string* error) {
  configured_route_delete_commands_.clear();
  configured_dns_interface_.clear();
  {
    std::lock_guard<std::mutex> lock(mutex_);
    tun_interface_index_.reset();
    upstream_interface_index_.reset();
    has_traffic_sample_ = false;
    last_upload_counter_sample_ = 0;
    last_download_counter_sample_ = 0;
    accumulated_upload_bytes_ = 0;
    accumulated_download_bytes_ = 0;
    last_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
    has_process_traffic_sample_ = false;
    last_process_upload_counter_sample_ = 0;
    last_process_download_counter_sample_ = 0;
    accumulated_process_upload_bytes_ = 0;
    accumulated_process_download_bytes_ = 0;
    last_process_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
    has_upstream_traffic_sample_ = false;
    last_upstream_upload_counter_sample_ = 0;
    last_upstream_download_counter_sample_ = 0;
    accumulated_upstream_upload_bytes_ = 0;
    accumulated_upstream_download_bytes_ = 0;
    last_upstream_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
  }
  constexpr const char* kTunInterfaceName = "xray-wintun";
  constexpr const char* kTunGateway = "172.19.0.1";

  std::optional<unsigned int> interface_index;
  for (int attempt = 0; attempt < 40; ++attempt) {
    interface_index = FindInterfaceIndexByFriendlyName(kTunInterfaceName);
    if (interface_index.has_value()) {
      LogLine("TUN adapter '" + std::string(kTunInterfaceName) + "' detected at attempt " +
              std::to_string(attempt) + " with index=" + std::to_string(*interface_index));
      break;
    }
    const bool still_running = IsProcessRunning();
    LogLine("TUN adapter '" + std::string(kTunInterfaceName) + "' not found at attempt " +
            std::to_string(attempt) + "/39. xray_running=" + (still_running ? "true" : "false"));
    Sleep(500);
  }

  if (!interface_index.has_value()) {
    LogLine("TUN adapter '" + std::string(kTunInterfaceName) + "' was NOT detected after 40 attempts.");
    if (process_) {
      DWORD exit_code = STILL_ACTIVE;
      if (GetExitCodeProcess(process_->pi.hProcess, &exit_code)) {
        LogLine("xray.exe exit_code=" + std::to_string(exit_code));
      }
      // Read first 4KB of xray stderr/stdout log if available.
      char temp_path[MAX_PATH];
      if (GetTempPathA(MAX_PATH, temp_path) != 0) {
        const std::string xray_log = std::string(temp_path) + "dart_v2ray_xray.log";
        HANDLE h = CreateFileA(xray_log.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (h != INVALID_HANDLE_VALUE) {
          char buffer[4096];
          DWORD read = 0;
          if (ReadFile(h, buffer, sizeof(buffer) - 1, &read, nullptr) && read > 0) {
            buffer[read] = '\0';
            LogLine("xray.exe output:\n" + std::string(buffer));
          }
          CloseHandle(h);
        }
      }
    }
    *error =
        "Xray TUN adapter 'xray-wintun' was not detected. Ensure wintun.dll is bundled and app is elevated.";
    return false;
  }

  {
    std::lock_guard<std::mutex> lock(mutex_);
    tun_interface_index_ = *interface_index;
  }

  std::string command_error;

  auto add_or_change_route = [this](const std::string& add_command,
                                    const std::string& change_command) -> std::string {
    std::string add_error = ExecuteSystemCommand(add_command);
    if (add_error.empty()) {
      return "";
    }
    std::string change_error = ExecuteSystemCommand(change_command);
    if (change_error.empty()) {
      return "";
    }
    return add_error + " | fallback-change: " + change_error;
  };

  // Exclude outbound server IPs from TUN default route to prevent xray routing
  // its own upstream connections back into the tunnel.
  const std::vector<std::string> outbound_hosts = ExtractOutboundDestinationHosts(effective_config);
  for (const auto& host : outbound_hosts) {
    const std::vector<std::string> destination_ips = ResolveHostToIpv4(host);
    if (destination_ips.empty()) {
      LogLine("TUN route exclusion: unable to resolve outbound host '" + host + "'");
      continue;
    }

    for (const auto& ip : destination_ips) {
      std::string gateway;
      unsigned int upstream_if_index = 0;
      if (!GetBestRouteForDestination(ip, &gateway, &upstream_if_index)) {
        LogLine("TUN route exclusion: unable to determine current route for " + ip);
        continue;
      }

      if (gateway == kTunGateway || upstream_if_index == *interface_index) {
        LogLine("TUN route exclusion: skipping " + ip +
                " because best route is already TUN gateway/interface.");
        continue;
      }

      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!upstream_interface_index_.has_value()) {
          upstream_interface_index_ = upstream_if_index;
        }
      }

      const std::string add_host_route =
          "route add " + ip + " mask 255.255.255.255 " + gateway +
          " if " + std::to_string(upstream_if_index) + " metric 3";
      const std::string change_host_route =
          "route change " + ip + " mask 255.255.255.255 " + gateway +
          " if " + std::to_string(upstream_if_index) + " metric 3";
      command_error = add_or_change_route(add_host_route, change_host_route);
      if (!command_error.empty()) {
        LogLine("TUN route exclusion failed for " + ip + ": " + command_error);
        continue;
      }

      configured_route_delete_commands_.push_back(
          "route delete " + ip + " mask 255.255.255.255 " + gateway +
          " if " + std::to_string(upstream_if_index));
      LogLine("TUN route exclusion added: " + ip + " via " + gateway +
              " if " + std::to_string(upstream_if_index));
    }
  }

  // Assign static IP to the TUN interface so Windows can actually use it.
  std::string ip_command =
      "netsh interface ipv4 set address name=\"" + std::string(kTunInterfaceName) +
      "\" static 172.19.0.2 255.255.255.252 " + std::string(kTunGateway);
  command_error = ExecuteSystemCommand(ip_command);
  if (!command_error.empty()) {
    *error = "Unable to set TUN interface address: " + command_error;
    return false;
  }
  LogLine("TUN interface IP set to 172.19.0.2/30 gateway=" + std::string(kTunGateway));

  const std::string add_default_route =
      "route add 0.0.0.0 mask 0.0.0.0 " + std::string(kTunGateway) +
      " if " + std::to_string(*interface_index) + " metric 6";
  const std::string change_default_route =
      "route change 0.0.0.0 mask 0.0.0.0 " + std::string(kTunGateway) +
      " if " + std::to_string(*interface_index) + " metric 6";
  command_error = add_or_change_route(add_default_route, change_default_route);
  if (!command_error.empty()) {
    *error = "Unable to add default route for xray-wintun: " + command_error;
    return false;
  }
  configured_route_delete_commands_.push_back(
      "route delete 0.0.0.0 mask 0.0.0.0 " + std::string(kTunGateway) +
      " if " + std::to_string(*interface_index));

  for (const auto& subnet : options.bypass_subnets) {
    if (subnet == "0.0.0.0/0") {
      continue;
    }

    if (subnet.find(':') != std::string::npos) {
      LogLine("Skipping IPv6 bypass route on Windows route manager: " + subnet);
      continue;
    }

    std::string network;
    std::string netmask;
    if (!ParseIpv4Cidr(subnet, &network, &netmask)) {
      LogLine("Skipping invalid bypass subnet: " + subnet);
      continue;
    }

    const std::string route_command =
        "route add " + EscapeForCmd(network) + " mask " + EscapeForCmd(netmask) + " " +
        std::string(kTunGateway) + " if " + std::to_string(*interface_index);
    const std::string route_change_command =
        "route change " + EscapeForCmd(network) + " mask " + EscapeForCmd(netmask) + " " +
        std::string(kTunGateway) + " if " + std::to_string(*interface_index);
    command_error = add_or_change_route(route_command, route_change_command);
    if (!command_error.empty()) {
      LogLine("Unable to add bypass route " + subnet + ": " + command_error);
      continue;
    }
    configured_route_delete_commands_.push_back(
        "route delete " + EscapeForCmd(network) + " mask " + EscapeForCmd(netmask) + " " +
        std::string(kTunGateway) + " if " + std::to_string(*interface_index));
  }

  {
    std::vector<std::string> effective_dns = options.dns_servers;
    if (effective_dns.empty()) {
      effective_dns = {"8.8.8.8", "1.1.1.1"};
    }
    const std::string dns_command =
        "netsh interface ipv4 set dnsservers name=\"" + std::string(kTunInterfaceName) +
        "\" static " + effective_dns.front() + " validate=no";
    command_error = ExecuteSystemCommand(dns_command);
    if (!command_error.empty()) {
      *error = "Unable to configure DNS on xray-wintun adapter: " + command_error;
      return false;
    }
    configured_dns_interface_ = kTunInterfaceName;

    for (size_t i = 1; i < effective_dns.size(); ++i) {
      const std::string secondary_dns_command =
          "netsh interface ipv4 add dnsservers name=\"" + std::string(kTunInterfaceName) +
          "\" address=" + effective_dns[i] + " index=" + std::to_string(i + 1) +
          " validate=no";
      ExecuteSystemCommand(secondary_dns_command);
    }
  }

  return true;
}

void DesktopV2rayCore::CleanupTunNetworking() {
  for (const auto& command : configured_route_delete_commands_) {
    ExecuteSystemCommand(command);
  }
  configured_route_delete_commands_.clear();

  if (!configured_dns_interface_.empty()) {
    ExecuteSystemCommand("netsh interface ipv4 set dnsservers name=\"" +
                         configured_dns_interface_ + "\" source=dhcp");
    configured_dns_interface_.clear();
  }

  std::lock_guard<std::mutex> lock(mutex_);
  tun_interface_index_.reset();
  upstream_interface_index_.reset();
  has_traffic_sample_ = false;
  last_upload_counter_sample_ = 0;
  last_download_counter_sample_ = 0;
  accumulated_upload_bytes_ = 0;
  accumulated_download_bytes_ = 0;
  last_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
  has_process_traffic_sample_ = false;
  last_process_upload_counter_sample_ = 0;
  last_process_download_counter_sample_ = 0;
  accumulated_process_upload_bytes_ = 0;
  accumulated_process_download_bytes_ = 0;
  last_process_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
  has_upstream_traffic_sample_ = false;
  last_upstream_upload_counter_sample_ = 0;
  last_upstream_download_counter_sample_ = 0;
  accumulated_upstream_upload_bytes_ = 0;
  accumulated_upstream_download_bytes_ = 0;
  last_upstream_traffic_sample_at_ = std::chrono::steady_clock::time_point{};
}
#endif

int DesktopV2rayCore::MeasureTcpDelay(const std::string& url) {
#if defined(_WIN32)
  if (IsVerboseLoggingEnabled()) {
    LogLine("MeasureTcpDelay requested for url=" + url);
  }
#endif
  std::string scheme = "https";
  std::string host_with_path = url;
  const auto sep = url.find("://");
  if (sep != std::string::npos) {
    scheme = url.substr(0, sep);
    host_with_path = url.substr(sep + 3);
  }

  auto slash = host_with_path.find('/');
  std::string host_port = slash == std::string::npos ? host_with_path : host_with_path.substr(0, slash);

  std::string host = host_port;
  std::string port = scheme == "http" ? "80" : "443";

  auto colon = host_port.rfind(':');
  if (colon != std::string::npos && host_port.find(']') == std::string::npos) {
    host = host_port.substr(0, colon);
    port = host_port.substr(colon + 1);
  }

#if defined(_WIN32)
  WSADATA wsa_data;
  if (WSAStartup(MAKEWORD(2, 2), &wsa_data) != 0) {
    LogLine("MeasureTcpDelay failed: WSAStartup failed.");
    return -1;
  }
#endif

  addrinfo hints{};
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_family = AF_UNSPEC;

  addrinfo* result = nullptr;
  if (getaddrinfo(host.c_str(), port.c_str(), &hints, &result) != 0) {
#if defined(_WIN32)
    WSACleanup();
    LogLine("MeasureTcpDelay failed: getaddrinfo failed for host=" + host + " port=" + port);
#endif
    return -1;
  }

  int delay_ms = -1;

  for (addrinfo* ptr = result; ptr != nullptr; ptr = ptr->ai_next) {
#if defined(_WIN32)
    SOCKET sock = socket(ptr->ai_family, ptr->ai_socktype, ptr->ai_protocol);
    if (sock == INVALID_SOCKET) {
      continue;
    }
#else
    int sock = socket(ptr->ai_family, ptr->ai_socktype, ptr->ai_protocol);
    if (sock < 0) {
      continue;
    }
#endif

    const auto start = std::chrono::steady_clock::now();
    const int connect_result = connect(sock, ptr->ai_addr, static_cast<int>(ptr->ai_addrlen));
    if (connect_result == 0) {
      delay_ms = static_cast<int>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::steady_clock::now() - start)
                                .count());
#if defined(_WIN32)
      closesocket(sock);
#else
      close(sock);
#endif
      break;
    }

#if defined(_WIN32)
    closesocket(sock);
#else
    close(sock);
#endif
  }

  freeaddrinfo(result);
#if defined(_WIN32)
  WSACleanup();
  LogLine("MeasureTcpDelay completed for url=" + url + " delay_ms=" + std::to_string(delay_ms));
#endif

  return delay_ms;
}

void DesktopV2rayCore::StartAutoDisconnectTimer() {
  StopAutoDisconnectTimer();
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stop_timer_ = false;
  }
  auto_disconnect_thread_ = std::thread([this]() {
    std::unique_lock<std::mutex> lock(mutex_);
    while (!stop_timer_) {
      if (!auto_disconnect_deadline_.has_value()) {
        timer_cv_.wait(lock, [this]() {
          return stop_timer_ || auto_disconnect_deadline_.has_value();
        });
        continue;
      }

      if (timer_cv_.wait_until(lock, auto_disconnect_deadline_.value(), [this]() {
            return stop_timer_;
          })) {
        break;
      }

      if (!stop_timer_ && auto_disconnect_deadline_.has_value() &&
          std::chrono::steady_clock::now() >= auto_disconnect_deadline_.value()) {
        lock.unlock();
        Stop(true);
        lock.lock();
        break;
      }
    }
  });
}

void DesktopV2rayCore::StopAutoDisconnectTimer() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stop_timer_ = true;
  }
  timer_cv_.notify_all();
  if (auto_disconnect_thread_.joinable()) {
    if (auto_disconnect_thread_.get_id() == std::this_thread::get_id()) {
      return;
    }
    auto_disconnect_thread_.join();
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stop_timer_ = false;
  }
}

}  // namespace dart_v2ray
