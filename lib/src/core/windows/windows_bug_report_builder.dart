import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../models/connection_status.dart';

/// Builds Windows diagnostics payloads suitable for bug-report submission.
class WindowsBugReportBuilder {
  /// Builds a generic bug-report map with platform, status, and log details.
  static Future<Map<String, dynamic>> build({
    required Future<Map<String, dynamic>> Function({int maxBytes})
    debugLogsFetcher,
    required ConnectionStatus latestStatus,
    int tailMaxBytes = 16384,
    bool includeLatestStatus = true,
    bool includeLogFiles = true,
    int fullLogMaxBytes = 262144,
  }) async {
    final int boundedTailBytes = tailMaxBytes.clamp(1024, 262144).toInt();
    final int boundedFullLogBytes =
        fullLogMaxBytes.clamp(4096, 1048576).toInt();

    final Map<String, dynamic> report = <String, dynamic>{
      'schema_version': 1,
      'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
      'platform': <String, dynamic>{
        'operating_system': Platform.operatingSystem,
        'operating_system_version': Platform.operatingSystemVersion,
      },
      'windows_supported': Platform.isWindows,
      'tail_max_bytes': boundedTailBytes,
      'full_log_max_bytes': boundedFullLogBytes,
    };

    if (!Platform.isWindows) {
      report['reason'] = 'windows_only';
      return report;
    }

    final Map<String, dynamic> windowsLogs = await debugLogsFetcher(
      maxBytes: boundedTailBytes,
    );
    report['windows_debug_logs'] = windowsLogs;

    if (includeLatestStatus) {
      report['latest_status'] = latestStatus.toMap();
    }

    if (includeLogFiles) {
      report['windows_log_files'] = await _readWindowsLogFiles(
        windowsLogs,
        maxBytes: boundedFullLogBytes,
      );
    }

    return report;
  }

  static Future<Map<String, dynamic>> _readWindowsLogFiles(
    Map<String, dynamic> windowsLogs, {
    required int maxBytes,
  }) async {
    final String pluginLogPath =
        windowsLogs['plugin_log_path']?.toString() ?? '';
    final String xrayLogPath = windowsLogs['xray_log_path']?.toString() ?? '';

    return <String, dynamic>{
      'plugin_log': await _readLogFileTail(pluginLogPath, maxBytes: maxBytes),
      'xray_log': await _readLogFileTail(xrayLogPath, maxBytes: maxBytes),
    };
  }

  static Future<Map<String, dynamic>> _readLogFileTail(
    String path, {
    required int maxBytes,
  }) async {
    if (path.isEmpty) {
      return <String, dynamic>{
        'path': path,
        'exists': false,
        'error': 'empty_path',
      };
    }

    final File file = File(path);
    try {
      final bool exists = await file.exists();
      if (!exists) {
        return <String, dynamic>{
          'path': path,
          'exists': false,
          'error': 'file_not_found',
        };
      }

      final int fileSize = await file.length();
      final int bytesToRead = min(fileSize, maxBytes);

      final RandomAccessFile handle = await file.open(mode: FileMode.read);
      try {
        await handle.setPosition(fileSize - bytesToRead);
        final List<int> data = await handle.read(bytesToRead);
        return <String, dynamic>{
          'path': path,
          'exists': true,
          'file_size_bytes': fileSize,
          'bytes_read': data.length,
          'truncated': fileSize > bytesToRead,
          'content': utf8.decode(data, allowMalformed: true),
        };
      } finally {
        await handle.close();
      }
    } catch (error) {
      return <String, dynamic>{
        'path': path,
        'exists': false,
        'error': error.toString(),
      };
    }
  }
}
