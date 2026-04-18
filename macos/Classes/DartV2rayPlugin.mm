#import "DartV2rayPlugin.h"

#import <Cocoa/Cocoa.h>
#import <NetworkExtension/NetworkExtension.h>

#include <climits>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "../../shared/desktop_v2ray_core.h"

using dart_v2ray::DesktopV2rayCore;

static NSString* const kAutoDisconnectTimestampKey = @"dart_v2ray_auto_disconnect_timestamp";

static bool ExtractBool(NSDictionary* args, NSString* key, bool default_value) {
  if (![args isKindOfClass:[NSDictionary class]]) {
    return default_value;
  }
  id value = args[key];
  if ([value isKindOfClass:[NSNumber class]]) {
    return [(NSNumber*)value boolValue];
  }
  return default_value;
}

static NSString* ExtractOptionalString(NSDictionary* args, NSString* key) {
  if (![args isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  id value = args[key];
  if ([value isKindOfClass:[NSString class]]) {
    NSString* string_value = (NSString*)value;
    return string_value.length > 0 ? string_value : nil;
  }
  return nil;
}

static NSDictionary* ExtractOptionalDictionary(NSDictionary* args, NSString* key) {
  if (![args isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  id value = args[key];
  if ([value isKindOfClass:[NSDictionary class]]) {
    return (NSDictionary*)value;
  }
  return nil;
}

static NSArray<NSString*>* ExtractStringArray(NSDictionary* args, NSString* key) {
  if (![args isKindOfClass:[NSDictionary class]]) {
    return @[];
  }

  id raw = args[key];
  if (![raw isKindOfClass:[NSArray class]]) {
    return @[];
  }

  NSMutableArray<NSString*>* values = [NSMutableArray array];
  for (id entry in (NSArray*)raw) {
    if (![entry isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString* value = (NSString*)entry;
    if (value.length == 0) {
      continue;
    }
    [values addObject:value];
  }
  return values;
}

static std::vector<std::string> ExtractStringList(NSDictionary* args, NSString* key) {
  std::vector<std::string> values;
  if (![args isKindOfClass:[NSDictionary class]]) {
    return values;
  }

  id raw = args[key];
  if (![raw isKindOfClass:[NSArray class]]) {
    return values;
  }

  for (id entry in (NSArray*)raw) {
    if (![entry isKindOfClass:[NSString class]]) {
      continue;
    }
    const char* utf8 = [(NSString*)entry UTF8String];
    values.emplace_back(utf8 != nullptr ? utf8 : "");
  }
  return values;
}

static std::optional<int> ExtractAutoDisconnectDuration(NSDictionary* args) {
  if (![args isKindOfClass:[NSDictionary class]]) {
    return std::nullopt;
  }
  id auto_disconnect = args[@"auto_disconnect"];
  if (![auto_disconnect isKindOfClass:[NSDictionary class]]) {
    return std::nullopt;
  }
  id duration = ((NSDictionary*)auto_disconnect)[@"duration"];
  if (![duration isKindOfClass:[NSNumber class]]) {
    return std::nullopt;
  }
  const NSInteger value = [(NSNumber*)duration integerValue];
  if (value <= 0 || value > INT_MAX) {
    return std::nullopt;
  }
  return static_cast<int>(value);
}

static NSString* ExtractUrlOrDefault(NSDictionary* args) {
  if (![args isKindOfClass:[NSDictionary class]]) {
    return @"https://google.com/generate_204";
  }
  id url = args[@"url"];
  if (![url isKindOfClass:[NSString class]] || [(NSString*)url length] == 0) {
    return @"https://google.com/generate_204";
  }
  return (NSString*)url;
}

static NSDictionary* ConvertStringMapToNSDictionary(
    const std::map<std::string, std::string>& values) {
  NSMutableDictionary* dictionary =
      [NSMutableDictionary dictionaryWithCapacity:values.size()];
  for (const auto& entry : values) {
    NSString* key = [NSString stringWithUTF8String:entry.first.c_str()];
    NSString* value = [NSString stringWithUTF8String:entry.second.c_str()];
    if (key == nil || value == nil) {
      continue;
    }
    dictionary[key] = value;
  }
  return dictionary;
}

static NSString* VpnStatusToStateString(NEVPNStatus status) {
  switch (status) {
    case NEVPNStatusConnected:
      return @"CONNECTED";
    case NEVPNStatusConnecting:
    case NEVPNStatusReasserting:
      return @"CONNECTING";
    case NEVPNStatusDisconnecting:
      return @"DISCONNECTING";
    case NEVPNStatusInvalid:
    case NEVPNStatusDisconnected:
    default:
      return @"DISCONNECTED";
  }
}

static NSInteger ParseIntegerString(NSString* value, NSInteger fallback_value) {
  if (![value isKindOfClass:[NSString class]] || value.length == 0) {
    return fallback_value;
  }

  NSScanner* scanner = [NSScanner scannerWithString:value];
  NSInteger parsed = 0;
  if (![scanner scanInteger:&parsed]) {
    return fallback_value;
  }
  return parsed;
}

@interface DartV2rayPlugin () <FlutterStreamHandler> {
  std::unique_ptr<DesktopV2rayCore> _core;
  FlutterEventSink _statusSink;
  NSTimer* _statusTimer;

  NETunnelProviderManager* _packetTunnelManager;
  id _vpnStatusObserver;

  NSString* _providerBundleIdentifier;
  NSString* _groupIdentifier;
  NSString* _appName;

  BOOL _usingPacketTunnel;
  BOOL _packetStatusRefreshInFlight;
  NSDate* _packetConnectedAt;
  uint64_t _packetUploadTotal;
  uint64_t _packetDownloadTotal;
  uint64_t _packetUploadSpeed;
  uint64_t _packetDownloadSpeed;
}

- (void)configureFromInitializeArgs:(NSDictionary*)args;
- (void)loadExistingPacketTunnelManagerIfAvailable;
- (BOOL)isPacketTunnelConnectionActive;
- (BOOL)shouldUsePacketTunnelStatus;

- (void)startDesktopCoreWithArguments:(NSDictionary*)args result:(FlutterResult)result;
- (void)startPacketTunnelWithArguments:(NSDictionary*)args result:(FlutterResult)result;
- (NSString*)stopPacketTunnelIfNeeded;

- (void)loadOrCreatePacketTunnelManagerWithCompletion:
    (void (^)(NETunnelProviderManager* _Nullable manager, NSError* _Nullable error))completion;
- (void)applyPacketTunnelConfigurationToManager:(NETunnelProviderManager*)manager
                                      arguments:(NSDictionary*)args
                                         config:(NSString*)config;

- (void)observePacketTunnelStatusIfNeeded;
- (void)sendProviderMessage:(NSString*)message
                 completion:(void (^)(NSData* _Nullable data, NSError* _Nullable error))completion;

- (NSUserDefaults*)autoDisconnectDefaults;
- (BOOL)wasPacketAutoDisconnected;
- (int64_t)packetAutoDisconnectTimestamp;
- (void)clearPacketAutoDisconnectFlag;

- (void)emitCoreStatus;
- (void)refreshPacketTunnelStatusAndEmit;
- (NSArray<NSString*>*)buildPacketTunnelPayloadWithState:(NSString*)state
                                                remaining:(NSString*)remaining;
- (void)resetPacketTunnelCounters;

@end

@implementation DartV2rayPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* method_channel = [FlutterMethodChannel
      methodChannelWithName:@"dart_v2ray"
            binaryMessenger:[registrar messenger]];

  FlutterEventChannel* status_channel = [FlutterEventChannel
      eventChannelWithName:@"dart_v2ray/status"
           binaryMessenger:[registrar messenger]];

  DartV2rayPlugin* instance = [[DartV2rayPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:method_channel];
  [status_channel setStreamHandler:instance];
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _core = std::make_unique<DesktopV2rayCore>();
    _statusSink = nil;
    _statusTimer = nil;

    _packetTunnelManager = nil;
    _vpnStatusObserver = nil;
    _providerBundleIdentifier = nil;
    _groupIdentifier = nil;
    _appName = @"VPN";

    _usingPacketTunnel = NO;
    _packetStatusRefreshInFlight = NO;
    _packetConnectedAt = nil;
    _packetUploadTotal = 0;
    _packetDownloadTotal = 0;
    _packetUploadSpeed = 0;
    _packetDownloadSpeed = 0;
  }
  return self;
}

- (void)dealloc {
  [self stopStatusTimer];

  if (_vpnStatusObserver != nil) {
    [[NSNotificationCenter defaultCenter] removeObserver:_vpnStatusObserver];
    _vpnStatusObserver = nil;
  }

  (void)[self stopPacketTunnelIfNeeded];
  if (_core) {
    _core->Stop();
  }
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString* method = call.method;
  NSDictionary* args = [call.arguments isKindOfClass:[NSDictionary class]]
                            ? (NSDictionary*)call.arguments
                            : nil;

  if ([method isEqualToString:@"requestPermission"]) {
    result(@(YES));
    return;
  }

  if ([method isEqualToString:@"initializeVless"]) {
    [self configureFromInitializeArgs:args];
    [self observePacketTunnelStatusIfNeeded];
    [self loadExistingPacketTunnelManagerIfAvailable];

    const std::string init_error = _core->Initialize();
    if (!init_error.empty()) {
      result([FlutterError errorWithCode:@"initialize_failed"
                                 message:[NSString stringWithUTF8String:init_error.c_str()]
                                 details:nil]);
      return;
    }

    result(nil);
    return;
  }

  if ([method isEqualToString:@"configureWindowsDebugLogging"]) {
    DesktopV2rayCore::WindowsDebugLoggingOptions options;
    options.enable_file_logging = ExtractBool(args, @"enable_file_log", false);
    options.enable_verbose_logging = ExtractBool(args, @"enable_verbose_log", false);
    options.capture_xray_stdio = ExtractBool(args, @"capture_xray_io", false);
    options.clear_existing_logs = ExtractBool(args, @"clear_existing_logs", false);
    _core->ConfigureWindowsDebugLogging(options);
    result(nil);
    return;
  }

  if ([method isEqualToString:@"startVless"]) {
    if (![args isKindOfClass:[NSDictionary class]]) {
      result([FlutterError errorWithCode:@"invalid_arguments"
                                 message:@"startVless requires a map argument."
                                 details:nil]);
      return;
    }

    const bool require_tun = ExtractBool(args, @"require_tun", false);
    if (require_tun) {
      [self startPacketTunnelWithArguments:args result:result];
    } else {
      [self startDesktopCoreWithArguments:args result:result];
    }
    return;
  }

  if ([method isEqualToString:@"stopVless"]) {
    NSString* packet_error = [self stopPacketTunnelIfNeeded];
    const std::string stop_error = _core->Stop();

    if (packet_error != nil) {
      result([FlutterError errorWithCode:@"stop_failed"
                                 message:packet_error
                                 details:nil]);
      return;
    }

    if (!stop_error.empty()) {
      result([FlutterError errorWithCode:@"stop_failed"
                                 message:[NSString stringWithUTF8String:stop_error.c_str()]
                                 details:nil]);
      return;
    }

    [self emitStatus];
    result(nil);
    return;
  }

  if ([method isEqualToString:@"getCoreVersion"]) {
    const std::string version = _core->GetCoreVersion();
    NSString* value = [NSString stringWithUTF8String:version.c_str()];
    result(value != nil ? value : @"xray-unavailable");
    return;
  }

  if ([method isEqualToString:@"getServerDelay"]) {
    NSString* url = ExtractUrlOrDefault(args);
    const char* url_utf8 = [url UTF8String];
    const int delay = _core->GetServerDelay(url_utf8 != nullptr ? url_utf8 : "");
    result(@(delay));
    return;
  }

  if ([method isEqualToString:@"getConnectedServerDelay"]) {
    NSString* url = ExtractUrlOrDefault(args);
    if ([self shouldUsePacketTunnelStatus]) {
      NSString* message = [@"xray_delay" stringByAppendingString:url ?: @""];
      [self sendProviderMessage:message
                     completion:^(NSData* _Nullable data, NSError* _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (error != nil || data == nil) {
            result(@(-1));
            return;
          }

          NSString* response = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
          NSInteger parsed = ParseIntegerString(response, -1);
          result(@((int)parsed));
        });
      }];
      return;
    }

    const char* url_utf8 = [url UTF8String];
    const int delay = _core->GetConnectedServerDelay(url_utf8 != nullptr ? url_utf8 : "");
    result(@(delay));
    return;
  }

  if ([method isEqualToString:@"updateAutoDisconnectTime"]) {
    int additional_seconds = 0;
    id value = args[@"additional_seconds"];
    if ([value isKindOfClass:[NSNumber class]]) {
      additional_seconds = [(NSNumber*)value intValue];
    }

    if ([self shouldUsePacketTunnelStatus]) {
      NSString* message = [NSString stringWithFormat:@"auto_disconnect_update:%d", additional_seconds];
      [self sendProviderMessage:message
                     completion:^(NSData* _Nullable data, NSError* _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (error != nil || data == nil) {
            result(@(-1));
            return;
          }

          NSString* response = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
          NSInteger parsed = ParseIntegerString(response, -1);
          result(@((int)parsed));
        });
      }];
      return;
    }

    result(@(_core->UpdateAutoDisconnectTime(additional_seconds)));
    return;
  }

  if ([method isEqualToString:@"getRemainingAutoDisconnectTime"]) {
    if ([self shouldUsePacketTunnelStatus]) {
      [self sendProviderMessage:@"auto_disconnect_remaining"
                     completion:^(NSData* _Nullable data, NSError* _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (error != nil || data == nil) {
            result(@(-1));
            return;
          }

          NSString* response = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
          NSInteger parsed = ParseIntegerString(response, -1);
          result(@((int)parsed));
        });
      }];
      return;
    }

    result(@(_core->GetRemainingAutoDisconnectTime()));
    return;
  }

  if ([method isEqualToString:@"cancelAutoDisconnect"]) {
    if ([self shouldUsePacketTunnelStatus]) {
      [self sendProviderMessage:@"auto_disconnect_cancel"
                     completion:^(NSData* _Nullable data, NSError* _Nullable error) {
        (void)data;
        (void)error;
        dispatch_async(dispatch_get_main_queue(), ^{ result(nil); });
      }];
      return;
    }

    _core->CancelAutoDisconnect();
    result(nil);
    return;
  }

  if ([method isEqualToString:@"wasAutoDisconnected"]) {
    const bool desktop_value = _core->WasAutoDisconnected();
    const bool packet_value = [self wasPacketAutoDisconnected];
    result(@(desktop_value || packet_value));
    return;
  }

  if ([method isEqualToString:@"clearAutoDisconnectFlag"]) {
    _core->ClearAutoDisconnectFlag();
    [self clearPacketAutoDisconnectFlag];
    result(nil);
    return;
  }

  if ([method isEqualToString:@"getAutoDisconnectTimestamp"]) {
    const int64_t desktop_timestamp = _core->GetAutoDisconnectTimestamp();
    const int64_t packet_timestamp = [self packetAutoDisconnectTimestamp];
    result(@((long long)MAX(desktop_timestamp, packet_timestamp)));
    return;
  }

  if ([method isEqualToString:@"getWindowsTrafficSource"]) {
    result(ConvertStringMapToNSDictionary(_core->GetWindowsTrafficDebugInfo()));
    return;
  }

  if ([method isEqualToString:@"getWindowsDebugLogs"]) {
    int max_bytes = 16384;
    id value = args[@"max_bytes"];
    if ([value isKindOfClass:[NSNumber class]]) {
      max_bytes = [(NSNumber*)value intValue];
    }
    result(ConvertStringMapToNSDictionary(_core->GetWindowsDebugLogs(max_bytes)));
    return;
  }

  result(FlutterMethodNotImplemented);
}

- (void)configureFromInitializeArgs:(NSDictionary*)args {
  NSString* provider_base = ExtractOptionalString(args, @"providerBundleIdentifier");
  if (provider_base != nil) {
    if ([provider_base hasSuffix:@".XrayTunnel"]) {
      _providerBundleIdentifier = [provider_base copy];
    } else {
      _providerBundleIdentifier = [[provider_base stringByAppendingString:@".XrayTunnel"] copy];
    }
  } else {
    _providerBundleIdentifier = nil;
  }

  _groupIdentifier = [ExtractOptionalString(args, @"groupIdentifier") copy];

  NSString* custom_name = ExtractOptionalString(args, @"appName");
  if (custom_name != nil) {
    _appName = custom_name;
  } else {
    NSString* display_name =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (display_name.length > 0) {
      _appName = display_name;
    } else {
      NSString* bundle_name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
      _appName = bundle_name.length > 0 ? bundle_name : @"VPN";
    }
  }
}

- (void)loadExistingPacketTunnelManagerIfAvailable {
  if (_providerBundleIdentifier.length == 0) {
    return;
  }

  NSString* expected_bundle = [_providerBundleIdentifier copy];
  __weak DartV2rayPlugin* weak_self = self;
  [NETunnelProviderManager
      loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager*>* managers,
                                                    NSError* error) {
    if (error != nil) {
      return;
    }

    NETunnelProviderManager* matched = nil;
    for (NETunnelProviderManager* manager in managers) {
      if (![manager.protocolConfiguration isKindOfClass:[NETunnelProviderProtocol class]]) {
        continue;
      }
      NETunnelProviderProtocol* config = (NETunnelProviderProtocol*)manager.protocolConfiguration;
      if ([config.providerBundleIdentifier isEqualToString:expected_bundle]) {
        matched = manager;
        break;
      }
    }

    if (matched == nil) {
      return;
    }

    [matched loadFromPreferencesWithCompletionHandler:^(NSError* load_error) {
      if (load_error != nil) {
        return;
      }

      dispatch_async(dispatch_get_main_queue(), ^{
        DartV2rayPlugin* strong_self = weak_self;
        if (strong_self == nil) {
          return;
        }
        strong_self->_packetTunnelManager = matched;
        if ([strong_self isPacketTunnelConnectionActive]) {
          strong_self->_usingPacketTunnel = YES;
          [strong_self emitStatus];
        }
      });
    }];
  }];
}

- (BOOL)isPacketTunnelConnectionActive {
  if (_packetTunnelManager == nil) {
    return NO;
  }

  switch (_packetTunnelManager.connection.status) {
    case NEVPNStatusConnected:
    case NEVPNStatusConnecting:
    case NEVPNStatusDisconnecting:
    case NEVPNStatusReasserting:
      return YES;
    case NEVPNStatusInvalid:
    case NEVPNStatusDisconnected:
    default:
      return NO;
  }
}

- (BOOL)shouldUsePacketTunnelStatus {
  return _usingPacketTunnel || [self isPacketTunnelConnectionActive];
}

- (void)startDesktopCoreWithArguments:(NSDictionary*)args result:(FlutterResult)result {
  NSString* packet_stop_error = [self stopPacketTunnelIfNeeded];
  if (packet_stop_error != nil) {
    result([FlutterError errorWithCode:@"start_failed"
                               message:packet_stop_error
                               details:nil]);
    return;
  }

  id config_value = args[@"config"];
  if (![config_value isKindOfClass:[NSString class]]) {
    result([FlutterError errorWithCode:@"invalid_arguments"
                               message:@"Missing config JSON string."
                               details:nil]);
    return;
  }

  DesktopV2rayCore::StartOptions options;
  options.auto_disconnect_seconds = ExtractAutoDisconnectDuration(args);
  options.bypass_subnets = ExtractStringList(args, @"bypass_subnets");
  options.dns_servers = ExtractStringList(args, @"dns_servers");
  options.require_tun = false;
  options.proxy_only = true;

  const char* config_utf8 = [(NSString*)config_value UTF8String];
  const std::string start_error = _core->Start(config_utf8 != nullptr ? config_utf8 : "", options);
  if (!start_error.empty()) {
    result([FlutterError errorWithCode:@"start_failed"
                               message:[NSString stringWithUTF8String:start_error.c_str()]
                               details:nil]);
    return;
  }

  [self emitStatus];
  result(nil);
}

- (void)startPacketTunnelWithArguments:(NSDictionary*)args result:(FlutterResult)result {
  id config_value = args[@"config"];
  if (![config_value isKindOfClass:[NSString class]]) {
    result([FlutterError errorWithCode:@"invalid_arguments"
                               message:@"Missing config JSON string."
                               details:nil]);
    return;
  }

  if (_providerBundleIdentifier.length == 0 || _groupIdentifier.length == 0) {
    result([FlutterError
        errorWithCode:@"invalid_state"
              message:@"initialize() must provide providerBundleIdentifier and groupIdentifier before requireTun=true on macOS."
              details:nil]);
    return;
  }

  const std::string stop_error = _core->Stop();
  if (!stop_error.empty()) {
    result([FlutterError errorWithCode:@"start_failed"
                               message:[NSString stringWithUTF8String:stop_error.c_str()]
                               details:nil]);
    return;
  }

  NSString* config = (NSString*)config_value;
  __weak DartV2rayPlugin* weak_self = self;
  [self loadOrCreatePacketTunnelManagerWithCompletion:
      ^(NETunnelProviderManager* _Nullable manager, NSError* _Nullable manager_error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      DartV2rayPlugin* strong_self = weak_self;
      if (strong_self == nil) {
        return;
      }

      if (manager_error != nil || manager == nil) {
        NSString* message = manager_error.localizedDescription ?: @"Unable to load Packet Tunnel manager.";
        result([FlutterError errorWithCode:@"start_failed" message:message details:nil]);
        return;
      }

      [strong_self applyPacketTunnelConfigurationToManager:manager arguments:args config:config];

      [manager saveToPreferencesWithCompletionHandler:^(NSError* save_error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (save_error != nil) {
            result([FlutterError errorWithCode:@"start_failed"
                                       message:save_error.localizedDescription
                                       details:nil]);
            return;
          }

          [manager loadFromPreferencesWithCompletionHandler:^(NSError* load_error) {
            dispatch_async(dispatch_get_main_queue(), ^{
              if (load_error != nil) {
                result([FlutterError errorWithCode:@"start_failed"
                                           message:load_error.localizedDescription
                                           details:nil]);
                return;
              }

              NSError* start_error = nil;
              BOOL started = [manager.connection startVPNTunnelAndReturnError:&start_error];
              if (!started || start_error != nil) {
                NSString* message = start_error.localizedDescription ?: @"Failed to start Packet Tunnel.";
                result([FlutterError errorWithCode:@"start_failed" message:message details:nil]);
                return;
              }

              strong_self->_packetTunnelManager = manager;
              strong_self->_usingPacketTunnel = YES;
              strong_self->_packetStatusRefreshInFlight = NO;
              [strong_self resetPacketTunnelCounters];
              [strong_self emitStatus];

              result(nil);
            });
          }];
        });
      }];
    });
  }];
}

- (NSString*)stopPacketTunnelIfNeeded {
  if (_packetTunnelManager == nil && !_usingPacketTunnel) {
    return nil;
  }

  if (_packetTunnelManager != nil) {
    @try {
      [_packetTunnelManager.connection stopVPNTunnel];
    } @catch (NSException* exception) {
      return [NSString stringWithFormat:@"Failed to stop Packet Tunnel: %@", exception.reason];
    }
  }

  _usingPacketTunnel = NO;
  _packetStatusRefreshInFlight = NO;
  [self resetPacketTunnelCounters];
  return nil;
}

- (void)loadOrCreatePacketTunnelManagerWithCompletion:
    (void (^)(NETunnelProviderManager* _Nullable manager, NSError* _Nullable error))completion {
  if (_providerBundleIdentifier.length == 0) {
    NSError* error =
        [NSError errorWithDomain:@"dart_v2ray"
                            code:1
                        userInfo:@{NSLocalizedDescriptionKey : @"Provider bundle identifier is missing."}];
    completion(nil, error);
    return;
  }

  NSString* expected_bundle = [_providerBundleIdentifier copy];
  [NETunnelProviderManager
      loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager*>* managers,
                                                    NSError* error) {
    if (error != nil) {
      completion(nil, error);
      return;
    }

    NETunnelProviderManager* matched = nil;
    for (NETunnelProviderManager* manager in managers) {
      if (![manager.protocolConfiguration isKindOfClass:[NETunnelProviderProtocol class]]) {
        continue;
      }

      NETunnelProviderProtocol* config = (NETunnelProviderProtocol*)manager.protocolConfiguration;
      if ([config.providerBundleIdentifier isEqualToString:expected_bundle]) {
        matched = manager;
        break;
      }
    }

    if (matched == nil) {
      matched = [[NETunnelProviderManager alloc] init];
    }

    completion(matched, nil);
  }];
}

- (void)applyPacketTunnelConfigurationToManager:(NETunnelProviderManager*)manager
                                      arguments:(NSDictionary*)args
                                         config:(NSString*)config {
  NETunnelProviderProtocol* protocol = [[NETunnelProviderProtocol alloc] init];
  protocol.providerBundleIdentifier = _providerBundleIdentifier;
  protocol.serverAddress = @"Xray";

  NSMutableDictionary* provider_config = [NSMutableDictionary dictionary];

  NSData* config_data = [config dataUsingEncoding:NSUTF8StringEncoding];
  provider_config[@"xrayConfig"] = config_data != nil ? config_data : [NSData data];
  provider_config[@"dnsServers"] = ExtractStringArray(args, @"dns_servers");
  provider_config[@"groupIdentifier"] = _groupIdentifier ?: @"";

  NSString* remark = ExtractOptionalString(args, @"remark");
  if (remark != nil) {
    provider_config[@"remark"] = remark;
  }

  NSDictionary* auto_disconnect = ExtractOptionalDictionary(args, @"auto_disconnect");
  if (auto_disconnect != nil) {
    provider_config[@"autoDisconnect"] = auto_disconnect;
  }

  protocol.providerConfiguration = provider_config;

  manager.localizedDescription = _appName ?: @"VPN";
  manager.protocolConfiguration = protocol;
  manager.enabled = YES;
}

- (void)observePacketTunnelStatusIfNeeded {
  if (_vpnStatusObserver != nil) {
    return;
  }

  __weak DartV2rayPlugin* weak_self = self;
  _vpnStatusObserver = [[NSNotificationCenter defaultCenter]
      addObserverForName:NEVPNStatusDidChangeNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification* _Nonnull notification) {
    (void)notification;
    DartV2rayPlugin* strong_self = weak_self;
    if (strong_self == nil) {
      return;
    }
    [strong_self emitStatus];
  }];
}

- (void)sendProviderMessage:(NSString*)message
                 completion:(void (^)(NSData* _Nullable data, NSError* _Nullable error))completion {
  if (_packetTunnelManager == nil) {
    NSError* error =
        [NSError errorWithDomain:@"dart_v2ray"
                            code:2
                        userInfo:@{NSLocalizedDescriptionKey : @"Packet Tunnel manager is unavailable."}];
    completion(nil, error);
    return;
  }

  if (![_packetTunnelManager.connection isKindOfClass:[NETunnelProviderSession class]]) {
    NSError* error =
        [NSError errorWithDomain:@"dart_v2ray"
                            code:3
                        userInfo:@{NSLocalizedDescriptionKey : @"Invalid tunnel session type."}];
    completion(nil, error);
    return;
  }

  NETunnelProviderSession* session = (NETunnelProviderSession*)_packetTunnelManager.connection;
  NSData* data = [message dataUsingEncoding:NSUTF8StringEncoding];

  NSError* send_error = nil;
  BOOL accepted = [session sendProviderMessage:data
                                   returnError:&send_error
                               responseHandler:^(NSData* _Nullable response_data) {
    completion(response_data, nil);
  }];

  if (!accepted) {
    NSError* error = send_error;
    if (error == nil) {
      error = [NSError errorWithDomain:@"dart_v2ray"
                                  code:4
                              userInfo:@{NSLocalizedDescriptionKey : @"Provider did not accept message."}];
    }
    completion(nil, error);
  }
}

- (NSUserDefaults*)autoDisconnectDefaults {
  if (_groupIdentifier.length > 0) {
    NSUserDefaults* group_defaults = [[NSUserDefaults alloc] initWithSuiteName:_groupIdentifier];
    if (group_defaults != nil) {
      return group_defaults;
    }
  }
  return [NSUserDefaults standardUserDefaults];
}

- (BOOL)wasPacketAutoDisconnected {
  return [[self autoDisconnectDefaults] doubleForKey:kAutoDisconnectTimestampKey] > 0;
}

- (int64_t)packetAutoDisconnectTimestamp {
  return (int64_t)[[self autoDisconnectDefaults] doubleForKey:kAutoDisconnectTimestampKey];
}

- (void)clearPacketAutoDisconnectFlag {
  NSUserDefaults* defaults = [self autoDisconnectDefaults];
  [defaults removeObjectForKey:kAutoDisconnectTimestampKey];
  [defaults synchronize];
}

- (FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
  (void)arguments;
  _statusSink = [events copy];
  [self startStatusTimer];
  [self emitStatus];
  return nil;
}

- (FlutterError*)onCancelWithArguments:(id)arguments {
  (void)arguments;
  _statusSink = nil;
  [self stopStatusTimer];
  return nil;
}

- (void)startStatusTimer {
  if (_statusTimer != nil) {
    return;
  }

  _statusTimer = [NSTimer timerWithTimeInterval:1.0
                                         target:self
                                       selector:@selector(handleStatusTick:)
                                       userInfo:nil
                                        repeats:YES];
  [[NSRunLoop mainRunLoop] addTimer:_statusTimer forMode:NSRunLoopCommonModes];
}

- (void)stopStatusTimer {
  if (_statusTimer == nil) {
    return;
  }
  [_statusTimer invalidate];
  _statusTimer = nil;
}

- (void)handleStatusTick:(NSTimer*)timer {
  (void)timer;
  [self emitStatus];
}

- (void)emitCoreStatus {
  _core->PollProcessAndHandleExit();
  const std::vector<std::string> payload = _core->BuildStatusPayload();

  NSMutableArray* list = [NSMutableArray arrayWithCapacity:payload.size()];
  for (const std::string& item : payload) {
    NSString* value = [NSString stringWithUTF8String:item.c_str()];
    [list addObject:(value != nil ? value : @"")];
  }
  _statusSink(list);
}

- (void)refreshPacketTunnelStatusAndEmit {
  if (_statusSink == nil) {
    return;
  }

  if (_packetTunnelManager == nil) {
    _usingPacketTunnel = NO;
    [self emitCoreStatus];
    return;
  }

  NSString* state = VpnStatusToStateString(_packetTunnelManager.connection.status);
  if (![state isEqualToString:@"CONNECTED"]) {
    if ([state isEqualToString:@"DISCONNECTED"] && [self wasPacketAutoDisconnected]) {
      state = @"AUTO_DISCONNECTED";
    }

    if (![state isEqualToString:@"CONNECTING"] && ![state isEqualToString:@"DISCONNECTING"]) {
      _usingPacketTunnel = NO;
      _packetStatusRefreshInFlight = NO;
      [self resetPacketTunnelCounters];
    }

    _statusSink([self buildPacketTunnelPayloadWithState:state remaining:@""]);
    return;
  }

  _usingPacketTunnel = YES;
  if (_packetStatusRefreshInFlight) {
    return;
  }

  _packetStatusRefreshInFlight = YES;
  __weak DartV2rayPlugin* weak_self = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    DartV2rayPlugin* timeout_self = weak_self;
    if (timeout_self == nil) {
      return;
    }
    if (timeout_self->_packetStatusRefreshInFlight) {
      timeout_self->_packetStatusRefreshInFlight = NO;
    }
  });

  [self sendProviderMessage:@"xray_traffic"
                 completion:^(NSData* _Nullable data, NSError* _Nullable error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      DartV2rayPlugin* strong_self = weak_self;
      if (strong_self == nil) {
        return;
      }

      if (error == nil && data != nil) {
        NSString* response = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSArray<NSString*>* parts = [response componentsSeparatedByString:@","];
        if (parts.count >= 2) {
          NSInteger parsed_upload = ParseIntegerString(parts[0], -1);
          NSInteger parsed_download = ParseIntegerString(parts[1], -1);

          if (parsed_upload >= 0 && parsed_download >= 0) {
            uint64_t current_upload = (uint64_t)parsed_upload;
            uint64_t current_download = (uint64_t)parsed_download;

            if (strong_self->_packetUploadTotal <= current_upload) {
              strong_self->_packetUploadSpeed = current_upload - strong_self->_packetUploadTotal;
            } else {
              strong_self->_packetUploadSpeed = 0;
            }

            if (strong_self->_packetDownloadTotal <= current_download) {
              strong_self->_packetDownloadSpeed =
                  current_download - strong_self->_packetDownloadTotal;
            } else {
              strong_self->_packetDownloadSpeed = 0;
            }

            strong_self->_packetUploadTotal = current_upload;
            strong_self->_packetDownloadTotal = current_download;
          }
        }
      }

      [strong_self
          sendProviderMessage:@"auto_disconnect_remaining"
                   completion:^(NSData* _Nullable remaining_data, NSError* _Nullable remaining_error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          DartV2rayPlugin* inner_self = weak_self;
          if (inner_self == nil) {
            return;
          }

          NSString* remaining = @"";
          if (remaining_error == nil && remaining_data != nil) {
            NSString* response =
                [[NSString alloc] initWithData:remaining_data encoding:NSUTF8StringEncoding];
            NSInteger parsed_remaining = ParseIntegerString(response, -1);
            if (parsed_remaining >= 0) {
              remaining = [NSString stringWithFormat:@"%ld", (long)parsed_remaining];
            }
          }

          inner_self->_packetStatusRefreshInFlight = NO;
          inner_self->_statusSink(
              [inner_self buildPacketTunnelPayloadWithState:@"CONNECTED" remaining:remaining]);
        });
      }];
    });
  }];
}

- (NSArray<NSString*>*)buildPacketTunnelPayloadWithState:(NSString*)state
                                                remaining:(NSString*)remaining {
  if (![state isEqualToString:@"CONNECTED"]) {
    _packetConnectedAt = nil;
  } else if (_packetConnectedAt == nil) {
    _packetConnectedAt = [NSDate date];
  }

  int duration_seconds = 0;
  if (_packetConnectedAt != nil) {
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:_packetConnectedAt];
    if (elapsed > 0) {
      duration_seconds = (int)elapsed;
    }
  }

  const BOOL traffic_observed =
      _packetUploadSpeed > 0 || _packetDownloadSpeed > 0 || _packetUploadTotal > 0 ||
      _packetDownloadTotal > 0;

  NSString* connection_phase = @"DISCONNECTED";
  if ([state isEqualToString:@"CONNECTING"] || [state isEqualToString:@"DISCONNECTING"]) {
    connection_phase = @"CONNECTING";
  } else if ([state isEqualToString:@"AUTO_DISCONNECTED"]) {
    connection_phase = @"AUTO_DISCONNECTED";
  } else if ([state isEqualToString:@"CONNECTED"]) {
    connection_phase = traffic_observed ? @"ACTIVE" : @"READY";
  }

  NSString* traffic_source = @"";
  NSString* traffic_reason = @"";
  if ([state isEqualToString:@"CONNECTED"]) {
    traffic_source = @"packet_tunnel";
    traffic_reason = traffic_observed ? @"extension_stats" : @"extension_no_traffic";
  } else if ([state isEqualToString:@"AUTO_DISCONNECTED"]) {
    traffic_reason = @"auto_disconnect_expired";
  }

  const BOOL process_running =
      [state isEqualToString:@"CONNECTED"] || [state isEqualToString:@"CONNECTING"] ||
      [state isEqualToString:@"DISCONNECTING"];

  return @[
    [NSString stringWithFormat:@"%d", duration_seconds],
    [NSString stringWithFormat:@"%llu", (unsigned long long)_packetUploadSpeed],
    [NSString stringWithFormat:@"%llu", (unsigned long long)_packetDownloadSpeed],
    [NSString stringWithFormat:@"%llu", (unsigned long long)_packetUploadTotal],
    [NSString stringWithFormat:@"%llu", (unsigned long long)_packetDownloadTotal],
    state ?: @"DISCONNECTED",
    remaining ?: @"",
    connection_phase,
    @"tun",
    traffic_source,
    traffic_reason,
    process_running ? @"true" : @"false"
  ];
}

- (void)resetPacketTunnelCounters {
  _packetConnectedAt = nil;
  _packetUploadTotal = 0;
  _packetDownloadTotal = 0;
  _packetUploadSpeed = 0;
  _packetDownloadSpeed = 0;
}

- (void)emitStatus {
  if (_statusSink == nil) {
    return;
  }

  if ([self shouldUsePacketTunnelStatus]) {
    [self refreshPacketTunnelStatusAndEmit];
    return;
  }

  [self emitCoreStatus];
}

@end
