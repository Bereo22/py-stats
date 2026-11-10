import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'periods.dart';

class DayActivity {
  final String day;
  final double km;
  final Duration active;

  /// Active (startMs, endMs) spans within the day, used to spread time over hours.
  final List<(int, int)> intervals;

  const DayActivity(this.day, this.km, this.active, [this.intervals = const []]);

  static DayActivity empty(String day) => DayActivity(day, 0, Duration.zero);
}

class GpsPoint {
  final int t;
  final double lat;
  final double lng;
  final double acc;
  final double spd;
  GpsPoint(this.t, this.lat, this.lng, this.acc, this.spd);
}

/// Km and active time per day, computed from the gps and sessions logs.
Future<Map<String, DayActivity>> loadActivity(String dir, List<String> days, {DateTime? openUntil}) {
  final until = openUntil?.millisecondsSinceEpoch;
  return Isolate.run(() => computeActivity(dir, days, openUntilMs: until));
}

Map<String, DayActivity> computeActivity(String dir, List<String> days, {int? openUntilMs}) {
  final sessions = _sessionIntervals(dir, openUntilMs);
  final out = <String, DayActivity>{};
  for (final day in days) {
    final points = readGps(dir, day);
    final km = distanceKm(points);
    final dayStart = parseDayKey(day).millisecondsSinceEpoch;
    final dayEnd = parseDayKey(day).add(const Duration(days: 1)).millisecondsSinceEpoch;

    final daySessions = sessions.where((s) => s.$1 < dayEnd && s.$2 > dayStart);
    final intervals = daySessions.isNotEmpty
        ? [for (final s in daySessions) (max(s.$1, dayStart), min(s.$2, dayEnd))]
        : _intervalsFromGaps(points);
    final activeMs = intervals.fold<int>(0, (s, i) => s + max(0, i.$2 - i.$1));
    out[day] = DayActivity(day, km, Duration(milliseconds: activeMs), intervals);
  }
  return out;
}

/// Accurate fixes between [fromMs] and [toMs], read off the UI thread.
Future<List<GpsPoint>> loadRoute(String dir, int fromMs, int toMs) {
  final days = {
    dayKey(DateTime.fromMillisecondsSinceEpoch(fromMs)),
    dayKey(DateTime.fromMillisecondsSinceEpoch(toMs)),
  }.toList();
  return Isolate.run(() => [
        for (final d in days)
          for (final p in readGps(dir, d))
            if (p.t >= fromMs && p.t <= toMs && p.acc <= 50) p,
      ]);
}

List<GpsPoint> readGps(String dir, String day) {
  final f = File('$dir${Platform.pathSeparator}gps_$day.jsonl');
  if (!f.existsSync()) return [];
  final points = <GpsPoint>[];
  for (final line in f.readAsLinesSync()) {
    try {
      final j = jsonDecode(line) as Map<String, dynamic>;
      points.add(GpsPoint(
        (j['t'] as num).toInt(),
        (j['lat'] as num).toDouble(),
        (j['lng'] as num).toDouble(),
        (j['acc'] as num?)?.toDouble() ?? 99,
        (j['spd'] as num?)?.toDouble() ?? 0,
      ));
    } catch (_) {}
  }
  points.sort((a, b) => a.t.compareTo(b.t));
  return points;
}

/// Sums hops between accurate fixes, dropping GPS jitter while parked and teleport jumps.
/// Only fixes within [fromMs, toMs] are used when given.
double distanceKm(List<GpsPoint> points, {int? fromMs, int? toMs}) {
  GpsPoint? prev;
  var meters = 0.0;
  for (final p in points) {
    if (fromMs != null && p.t < fromMs) continue;
    if (toMs != null && p.t > toMs) break;
    if (p.acc > 35) continue;
    if (prev != null) {
      final d = haversineMeters(prev.lat, prev.lng, p.lat, p.lng);
      final dt = (p.t - prev.t) / 1000;
      final jitter = d < (prev.acc + p.acc) / 2 && p.spd < 1;
      final jump = dt <= 0 || d / dt > 45;
      if (jitter) continue;
      if (!jump) meters += d;
    }
    prev = p;
  }
  return meters / 1000;
}

/// Fix closest in time to [t], if one exists within [maxGap].
GpsPoint? nearestFix(List<GpsPoint> points, int t, {Duration maxGap = const Duration(minutes: 2)}) {
  GpsPoint? best;
  for (final p in points) {
    if (best == null || (p.t - t).abs() < (best.t - t).abs()) best = p;
  }
  if (best == null || (best.t - t).abs() > maxGap.inMilliseconds) return null;
  return best;
}

double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final h = pow(sin(dLat / 2), 2) + cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * pow(sin(dLng / 2), 2);
  return 2 * r * asin(sqrt(h));
}

/// Fallback for days recorded before session logging: gaps under 10 min count as active.
List<(int, int)> _intervalsFromGaps(List<GpsPoint> points) {
  final out = <(int, int)>[];
  int? start;
  int? end;
  for (final p in points) {
    if (start != null && p.t - end! < 10 * 60 * 1000) {
      end = p.t;
      continue;
    }
    if (start != null) out.add((start, end!));
    start = p.t;
    end = p.t;
  }
  if (start != null) out.add((start, end!));
  return out.where((i) => i.$2 > i.$1).toList();
}

/// (startMs, endMs) pairs. A session without a stop event ends at its last GPS fix,
/// or at [openUntilMs] when tracking is still running.
List<(int, int)> _sessionIntervals(String dir, int? openUntilMs) {
  final d = Directory(dir);
  if (!d.existsSync()) return [];
  final events = <(int, String)>[];
  for (final f in d.listSync().whereType<File>()) {
    if (!f.uri.pathSegments.last.startsWith('sessions_')) continue;
    for (final line in f.readAsLinesSync()) {
      try {
        final j = jsonDecode(line) as Map<String, dynamic>;
        events.add(((j['t'] as num).toInt(), j['ev'] as String));
      } catch (_) {}
    }
  }
  events.sort((a, b) => a.$1.compareTo(b.$1));

  final out = <(int, int)>[];
  int? open;
  for (final (t, ev) in events) {
    if (ev == 'start') {
      if (open != null) out.add((open, _lastFixBefore(dir, open, t)));
      open = t;
    } else if (ev == 'stop' && open != null) {
      out.add((open, t));
      open = null;
    }
  }
  if (open != null) {
    out.add((open, openUntilMs ?? _lastFixBefore(dir, open, null)));
  }
  return out;
}

/// Latest GPS fix after [from] and not after [to] (no upper bound when null).
int _lastFixBefore(String dir, int from, int? to) {
  var last = from;
  final f = DateTime.fromMillisecondsSinceEpoch(from);
  final t = to == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(to);
  final end = t.isBefore(f) ? f : t;
  final lastDay = DateTime(end.year, end.month, end.day);
  for (var day = DateTime(f.year, f.month, f.day);
      !day.isAfter(lastDay);
      day = DateTime(day.year, day.month, day.day + 1)) {
    for (final p in readGps(dir, dayKey(day))) {
      if (p.t > last && (to == null || p.t <= to)) last = p.t;
    }
  }
  return last;
}
