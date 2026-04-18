#include "include/dart_v2ray/dart_v2ray_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>
#include <optional>
#include <string>

#include "desktop_v2ray_core.h"

#define DART_V2RAY_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), dart_v2ray_plugin_get_type(), \
                              DartV2rayPlugin))

struct _DartV2rayPlugin {
  GObject parent_instance;
  dart_v2ray::DesktopV2rayCore* core;
  FlEventChannel* status_channel;
  FlEventSink* status_sink;
  guint status_timer_id;
};

G_DEFINE_TYPE(DartV2rayPlugin, dart_v2ray_plugin, g_object_get_type())

static gboolean push_status(gpointer user_data) {
  auto* self = DART_V2RAY_PLUGIN(user_data);
  if (self->status_sink == nullptr) {
    return G_SOURCE_REMOVE;
  }

  auto payload = self->core->BuildStatusPayload();
  g_autoptr(FlValue) list = fl_value_new_list();
  for (const auto& item : payload) {
    fl_value_append_take(list, fl_value_new_string(item.c_str()));
  }

  fl_event_sink_success(self->status_sink, list, nullptr);
  return G_SOURCE_CONTINUE;
}

static std::optional<int> extract_auto_disconnect_duration(FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return std::nullopt;
  }

  FlValue* auto_disconnect = fl_value_lookup_string(args, "auto_disconnect");
  if (auto_disconnect == nullptr || fl_value_get_type(auto_disconnect) != FL_VALUE_TYPE_MAP) {
    return std::nullopt;
  }

  FlValue* duration = fl_value_lookup_string(auto_disconnect, "duration");
  if (duration == nullptr || fl_value_get_type(duration) != FL_VALUE_TYPE_INT) {
    return std::nullopt;
  }

  const int value = static_cast<int>(fl_value_get_int(duration));
  return value > 0 ? std::optional<int>(value) : std::nullopt;
}

static const char* extract_url_or_default(FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return "https://google.com/generate_204";
  }

  FlValue* url = fl_value_lookup_string(args, "url");
  if (url == nullptr || fl_value_get_type(url) != FL_VALUE_TYPE_STRING) {
    return "https://google.com/generate_204";
  }

  return fl_value_get_string(url);
}

static FlMethodResponse* handle_method_call(DartV2rayPlugin* self,
                                            FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "requestPermission") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(true);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }

  if (strcmp(method, "initializeVless") == 0) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  if (strcmp(method, "startVless") == 0) {
    if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      return FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invalid_arguments", "startVless requires a map argument.", nullptr));
    }

    FlValue* config_value = fl_value_lookup_string(args, "config");
    if (config_value == nullptr || fl_value_get_type(config_value) != FL_VALUE_TYPE_STRING) {
      return FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invalid_arguments", "Missing config JSON string.", nullptr));
    }

    bool proxy_only = false;
    FlValue* proxy_only_value = fl_value_lookup_string(args, "proxy_only");
    if (proxy_only_value != nullptr &&
        fl_value_get_type(proxy_only_value) == FL_VALUE_TYPE_BOOL) {
      proxy_only = fl_value_get_bool(proxy_only_value);
    }

    const std::optional<int> duration = extract_auto_disconnect_duration(args);
    dart_v2ray::DesktopV2rayCore::StartOptions options;
    options.proxy_only = proxy_only;
    options.auto_disconnect_seconds = duration;

    const std::string error =
        self->core->Start(fl_value_get_string(config_value), options);
    if (!error.empty()) {
      return FL_METHOD_RESPONSE(
          fl_method_error_response_new("start_failed", error.c_str(), nullptr));
    }

    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  if (strcmp(method, "stopVless") == 0) {
    const std::string error = self->core->Stop();
    if (!error.empty()) {
      return FL_METHOD_RESPONSE(
          fl_method_error_response_new("stop_failed", error.c_str(), nullptr));
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  if (strcmp(method, "getCoreVersion") == 0) {
    g_autoptr(FlValue) result = fl_value_new_string(self->core->GetCoreVersion().c_str());
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }

  if (strcmp(method, "getServerDelay") == 0) {
    const int delay = self->core->GetServerDelay(extract_url_or_default(args));
    g_autoptr(FlValue) result = fl_value_new_int(delay);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }

  if (strcmp(method, "getConnectedServerDelay") == 0) {
    const int delay = self->core->GetConnectedServerDelay(extract_url_or_default(args));
    g_autoptr(FlValue) result = fl_value_new_int(delay);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }

  if (strcmp(method, "updateAutoDisconnectTime") == 0) {
    int additional = 0;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* value = fl_value_lookup_string(args, "additional_seconds");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
        additional = static_cast<int>(fl_value_get_int(value));
      }
    }
    g_autoptr(FlValue) result = fl_value_new_int(self->core->UpdateAutoDisconnectTime(additional));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }

  if (strcmp(method, "getRemainingAutoDisconnectTime") == 0) {
    g_autoptr(FlValue) result = fl_value_new_int(self->core->GetRemainingAutoDisconnectTime());
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }

  if (strcmp(method, "cancelAutoDisconnect") == 0) {
    self->core->CancelAutoDisconnect();
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  if (strcmp(method, "wasAutoDisconnected") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(self->core->WasAutoDisconnected());
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }

  if (strcmp(method, "clearAutoDisconnectFlag") == 0) {
    self->core->ClearAutoDisconnectFlag();
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  if (strcmp(method, "getAutoDisconnectTimestamp") == 0) {
    g_autoptr(FlValue) result = fl_value_new_int(self->core->GetAutoDisconnectTimestamp());
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }

  return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
}

static FlMethodErrorResponse* status_listen_cb(FlEventChannel* channel,
                                               FlValue* args,
                                               FlEventSink* events,
                                               gpointer user_data) {
  (void)channel;
  (void)args;
  auto* self = DART_V2RAY_PLUGIN(user_data);
  self->status_sink = events;
  if (self->status_timer_id == 0) {
    self->status_timer_id = g_timeout_add_seconds(1, push_status, self);
  }
  return nullptr;
}

static FlMethodErrorResponse* status_cancel_cb(FlEventChannel* channel,
                                               FlValue* args,
                                               gpointer user_data) {
  (void)channel;
  (void)args;
  auto* self = DART_V2RAY_PLUGIN(user_data);
  self->status_sink = nullptr;
  if (self->status_timer_id != 0) {
    g_source_remove(self->status_timer_id);
    self->status_timer_id = 0;
  }
  return nullptr;
}

static void dart_v2ray_plugin_dispose(GObject* object) {
  auto* self = DART_V2RAY_PLUGIN(object);

  if (self->status_timer_id != 0) {
    g_source_remove(self->status_timer_id);
    self->status_timer_id = 0;
  }
  self->status_sink = nullptr;
  self->status_channel = nullptr;

  delete self->core;
  self->core = nullptr;
  G_OBJECT_CLASS(dart_v2ray_plugin_parent_class)->dispose(object);
}

static void dart_v2ray_plugin_class_init(DartV2rayPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = dart_v2ray_plugin_dispose;
}

static void dart_v2ray_plugin_init(DartV2rayPlugin* self) {
  self->core = new dart_v2ray::DesktopV2rayCore();
  self->status_channel = nullptr;
  self->status_sink = nullptr;
  self->status_timer_id = 0;
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  auto* plugin = DART_V2RAY_PLUGIN(user_data);
  g_autoptr(FlMethodResponse) response = handle_method_call(plugin, method_call);
  fl_method_call_respond(method_call, response, nullptr);
}

void dart_v2ray_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  DartV2rayPlugin* plugin = DART_V2RAY_PLUGIN(
      g_object_new(dart_v2ray_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) method_codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) method_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "dart_v2ray",
      FL_METHOD_CODEC(method_codec));

  fl_method_channel_set_method_call_handler(method_channel, method_call_cb,
                                            g_object_ref(plugin), g_object_unref);

  g_autoptr(FlStandardMethodCodec) event_codec = fl_standard_method_codec_new();
  plugin->status_channel = fl_event_channel_new(fl_plugin_registrar_get_messenger(registrar),
                                                "dart_v2ray/status",
                                                FL_METHOD_CODEC(event_codec));

  fl_event_channel_set_stream_handlers(plugin->status_channel, status_listen_cb,
                                       status_cancel_cb, g_object_ref(plugin),
                                       g_object_unref);

  g_object_unref(plugin);
}

