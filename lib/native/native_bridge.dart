import 'package:flutter/services.dart';

class NativeStatus {
  final bool a11yEnabled;
  final bool a11yConnected;
  final String? foregroundPkg;
  final String? targetPkg;
  final List<String> seenPkgs;
  final DateTime? lastTargetEventAt;
  final DateTime? lastScreenWrittenAt;
  final int screensWritten;
  final bool tracking;
  final DateTime? trackingStartedAt;
  final bool ocrOnStart;
  final bool capturing;
  final DateTime? lastOcrAt;
  final double? lat;
  final double? lng;
  final double? accuracy;
  final DateTime? locationAt;
  final bool ignoringBatteryOptimizations;
  final String logDir;

  NativeStatus.fromMap(Map<dynamic, dynamic> m)
      : a11yEnabled = m['a11yEnabled'] == true,
        a11yConnected = m['a11yConnected'] == true,
        foregroundPkg = m['foregroundPkg'] as String?,
        targetPkg = m['targetPkg'] as String?,
        seenPkgs = ((m['seenPkgs'] as List?) ?? const []).cast<String>(),
        lastTargetEventAt = _time(m['lastTargetEventAt']),
        lastScreenWrittenAt = _time(m['lastScreenWrittenAt']),
        screensWritten = (m['screensWritten'] as int?) ?? 0,
        tracking = m['tracking'] == true,
        trackingStartedAt = _time(m['trackingStartedAt']),
        ocrOnStart = m['ocrOnStart'] == true,
        capturing = m['capturing'] == true,
        lastOcrAt = _time(m['lastOcrAt']),
        lat = (m['lastLocation'] as Map?)?['lat'] as double?,
        lng = (m['lastLocation'] as Map?)?['lng'] as double?,
        accuracy = (m['lastLocation'] as Map?)?['acc'] as double?,
        locationAt = _time((m['lastLocation'] as Map?)?['t']),
        ignoringBatteryOptimizations = m['ignoringBatteryOptimizations'] == true,
        logDir = (m['logDir'] as String?) ?? '';

  static DateTime? _time(Object? v) {
    final ms = (v as num?)?.toInt() ?? 0;
    return ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }
}

class NativeBridge {
  static const _channel = MethodChannel('tag_stats/native');

  static Future<NativeStatus> status() async =>
      NativeStatus.fromMap(await _channel.invokeMethod<Map>('getStatus') ?? {});

  static Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod('openAccessibilitySettings');
  static Future<void> openAppDetails() => _channel.invokeMethod('openAppDetails');
  static Future<void> openAutostartSettings() =>
      _channel.invokeMethod('openAutostartSettings');
  static Future<void> requestIgnoreBatteryOptimizations() =>
      _channel.invokeMethod('requestIgnoreBatteryOptimizations');

  static Future<void> startTracking() => _channel.invokeMethod('startTracking');
  static Future<void> stopTracking() => _channel.invokeMethod('stopTracking');

  /// Shows Android's screen-capture consent dialog; true if the user allowed it.
  static Future<bool> startCapture() async =>
      await _channel.invokeMethod<bool>('startCapture') ?? false;
  static Future<void> stopCapture() => _channel.invokeMethod('stopCapture');

  static Future<void> setOcrOnStart(bool value) =>
      _channel.invokeMethod('setOcrOnStart', {'value': value});

  static Future<void> setTargetPackage(String? pkg) =>
      _channel.invokeMethod('setTargetPackage', {'pkg': pkg});

  /// Returns the number of exported files (0 when there is nothing to share).
  static Future<int> exportLogs() async =>
      await _channel.invokeMethod<int>('exportLogs') ?? 0;
}
