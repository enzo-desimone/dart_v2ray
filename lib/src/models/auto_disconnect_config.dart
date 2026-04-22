/// Behavior executed when the auto-disconnect timer expires.
enum AutoDisconnectExpireBehavior {
  /// Disconnect without showing a local notification.
  disconnectSilently,

  /// Disconnect and show a local notification to the user.
  disconnectWithNotification,
}

/// Preferred formatter for the remaining-time label in notifications.
enum AutoDisconnectTimeFormat {
  /// Show hours, minutes, and seconds.
  withSeconds,

  /// Show hours and minutes only.
  withoutSeconds,
}

/// Auto-disconnect configuration passed to native implementations.
///
/// This is useful for "free minutes" models where the VPN must disconnect
/// automatically even if the app is in background or terminated.
class AutoDisconnectConfig {
  /// Maximum session duration in seconds.
  final int durationSeconds;

  /// Whether the notification should show the remaining time.
  final bool showRemainingTimeInNotification;

  /// Formatting style for remaining-time text.
  final AutoDisconnectTimeFormat timeFormat;

  /// Behavior to execute when the timer expires.
  final AutoDisconnectExpireBehavior onExpire;

  /// Optional custom text for the expiry notification.
  final String? expiredNotificationMessage;

  const AutoDisconnectConfig({
    required this.durationSeconds,
    this.showRemainingTimeInNotification = true,
    this.timeFormat = AutoDisconnectTimeFormat.withSeconds,
    this.onExpire = AutoDisconnectExpireBehavior.disconnectWithNotification,
    this.expiredNotificationMessage,
  }) : assert(durationSeconds >= 0);

  /// Returns a disabled configuration.
  const AutoDisconnectConfig.disabled()
    : durationSeconds = 0,
      showRemainingTimeInNotification = false,
      timeFormat = AutoDisconnectTimeFormat.withSeconds,
      onExpire = AutoDisconnectExpireBehavior.disconnectSilently,
      expiredNotificationMessage = null;

  /// Converts to a method-channel payload.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'duration': durationSeconds,
      'showRemainingTimeInNotification': showRemainingTimeInNotification,
      'timeFormat': timeFormat.index,
      'onExpire': onExpire.index,
      'expiredNotificationMessage': expiredNotificationMessage,
    };
  }
}
