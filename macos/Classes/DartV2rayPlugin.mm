#import "DartV2rayPlugin.h"

#import <Cocoa/Cocoa.h>

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>
#include <climits>

#include "../../shared/desktop_v2ray_core.h"

using dart_v2ray::DesktopV2rayCore;

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

@interface DartV2rayPlugin () <FlutterStreamHandler> {
  std::unique_ptr<DesktopV2rayCore> _core;
  FlutterEventSink _statusSink;
  NSTimer* _statusTimer;
}
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
  }
  return self;
}

- (void)dealloc {
  [self stopStatusTimer];
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

    id config_value = args[@"config"];
    if (![config_value isKindOfClass:[NSString class]]) {
      result([FlutterError errorWithCode:@"invalid_arguments"
                                 message:@"Missing config JSON string."
                                 details:nil]);
      return;
    }

    DesktopV2rayCore::StartOptions options;
    options.proxy_only = ExtractBool(args, @"proxy_only", false);
    options.auto_disconnect_seconds = ExtractAutoDisconnectDuration(args);
    options.bypass_subnets = ExtractStringList(args, @"bypass_subnets");
    options.dns_servers = ExtractStringList(args, @"dns_servers");
    options.require_tun = ExtractBool(args, @"windows_require_tun", false);

    const char* config_utf8 = [(NSString*)config_value UTF8String];
    const std::string start_error = _core->Start(config_utf8 != nullptr ? config_utf8 : "", options);
    if (!start_error.empty()) {
      result([FlutterError errorWithCode:@"start_failed"
                                 message:[NSString stringWithUTF8String:start_error.c_str()]
                                 details:nil]);
      return;
    }

    result(nil);
    return;
  }

  if ([method isEqualToString:@"stopVless"]) {
    const std::string stop_error = _core->Stop();
    if (!stop_error.empty()) {
      result([FlutterError errorWithCode:@"stop_failed"
                                 message:[NSString stringWithUTF8String:stop_error.c_str()]
                                 details:nil]);
      return;
    }
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
    result(@(_core->UpdateAutoDisconnectTime(additional_seconds)));
    return;
  }

  if ([method isEqualToString:@"getRemainingAutoDisconnectTime"]) {
    result(@(_core->GetRemainingAutoDisconnectTime()));
    return;
  }

  if ([method isEqualToString:@"cancelAutoDisconnect"]) {
    _core->CancelAutoDisconnect();
    result(nil);
    return;
  }

  if ([method isEqualToString:@"wasAutoDisconnected"]) {
    result(@(_core->WasAutoDisconnected()));
    return;
  }

  if ([method isEqualToString:@"clearAutoDisconnectFlag"]) {
    _core->ClearAutoDisconnectFlag();
    result(nil);
    return;
  }

  if ([method isEqualToString:@"getAutoDisconnectTimestamp"]) {
    result(@(_core->GetAutoDisconnectTimestamp()));
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

- (void)emitStatus {
  if (_statusSink == nil) {
    return;
  }

  _core->PollProcessAndHandleExit();
  const std::vector<std::string> payload = _core->BuildStatusPayload();

  NSMutableArray* list = [NSMutableArray arrayWithCapacity:payload.size()];
  for (const std::string& item : payload) {
    NSString* value = [NSString stringWithUTF8String:item.c_str()];
    [list addObject:(value != nil ? value : @"")];
  }
  _statusSink(list);
}

@end
