import 'package:dart_v2ray/dart_v2ray_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel methodChannel = MethodChannel('dart_v2ray');
  final MethodChannelDartV2ray platform = MethodChannelDartV2ray();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'getCoreVersion':
              return 'xray 1.8.0';
            case 'requestPermission':
              return true;
            case 'configureWindowsDebugLogging':
              return null;
            case 'getWindowsTrafficSource':
              return <String, dynamic>{
                'supported': 'true',
                'traffic_source': 'process_io',
              };
            case 'getWindowsDebugLogs':
              return <String, dynamic>{
                'supported': 'true',
                'plugin_log_tail': 'hello from plugin log',
              };
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('getCoreVersion delegates to method channel', () async {
    expect(await platform.getCoreVersion(), 'xray 1.8.0');
  });

  test('requestPermission delegates to method channel', () async {
    expect(await platform.requestPermission(), isTrue);
  });

  test('getWindowsTrafficDiagnostics returns decoded map', () async {
    final diagnostics = await platform.getWindowsTrafficDiagnostics();

    expect(diagnostics['supported'], 'true');
    expect(diagnostics['traffic_source'], 'process_io');
  });

  test('configureWindowsDebugLogging delegates to method channel', () async {
    await platform.configureWindowsDebugLogging(
      enableFileLog: true,
      enableVerboseLog: true,
      captureXrayIo: true,
      clearExistingLogs: true,
    );
  });

  test('getWindowsDebugLogs returns decoded map', () async {
    final logs = await platform.getWindowsDebugLogs();

    expect(logs['supported'], 'true');
    expect(logs['plugin_log_tail'], 'hello from plugin log');
  });
}
