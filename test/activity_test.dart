import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tag_stats/data/activity.dart';
import 'package:tag_stats/data/periods.dart';

void main() {
  late Directory dir;
  final day = DateTime(2026, 11, 3);
  final key = dayKey(day);

  setUp(() => dir = Directory.systemTemp.createTempSync('tag_stats_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String name, List<Map<String, Object>> lines) =>
      File('${dir.path}/$name').writeAsStringSync(lines.map(jsonEncode).join('\n'));

  int at(int h, int m, [int s = 0]) => DateTime(2026, 11, 3, h, m, s).millisecondsSinceEpoch;

  test('distance ignores parked jitter and teleport jumps', () {
    // ~111 m per 0.001° latitude, heading north every 10 s.
    write('gps_$key.jsonl', [
      for (var i = 0; i <= 10; i++) {'t': at(10, 0, i * 10), 'lat': 41.670 + i * 0.001, 'lng': 26.55, 'acc': 8, 'spd': 11},
      // parked: tiny jitter, not counted
      for (var i = 0; i < 5; i++) {'t': at(10, 2, i * 10), 'lat': 41.680 + (i.isEven ? 0.00002 : 0), 'lng': 26.55, 'acc': 10, 'spd': 0},
      // impossible jump, not counted
      {'t': at(10, 3), 'lat': 41.780, 'lng': 26.55, 'acc': 8, 'spd': 0},
      // inaccurate fix, skipped
      {'t': at(10, 3, 5), 'lat': 41.690, 'lng': 26.55, 'acc': 80, 'spd': 0},
    ]);
    final a = computeActivity(dir.path, [key])[key]!;
    expect(a.km, closeTo(1.11, 0.02));
  });

  test('active time comes from sessions, open session ends at last fix', () {
    write('gps_$key.jsonl', [
      {'t': at(9, 0), 'lat': 41.67, 'lng': 26.55, 'acc': 8, 'spd': 0},
      {'t': at(14, 30), 'lat': 41.67, 'lng': 26.55, 'acc': 8, 'spd': 0},
    ]);
    write('sessions_$key.jsonl', [
      {'t': at(8, 0), 'ev': 'start'},
      {'t': at(12, 0), 'ev': 'stop'},
      {'t': at(13, 0), 'ev': 'start'},
    ]);
    final a = computeActivity(dir.path, [key])[key]!;
    expect(a.active, const Duration(hours: 5, minutes: 30));

    final running = computeActivity(dir.path, [key], openUntilMs: at(15, 0))[key]!;
    expect(running.active, const Duration(hours: 6));
  });

  test('without sessions, active time falls back to gps gaps under 10 min', () {
    write('gps_$key.jsonl', [
      {'t': at(9, 0), 'lat': 41.67, 'lng': 26.55, 'acc': 8, 'spd': 0},
      {'t': at(9, 5), 'lat': 41.67, 'lng': 26.55, 'acc': 8, 'spd': 0},
      {'t': at(11, 0), 'lat': 41.67, 'lng': 26.55, 'acc': 8, 'spd': 0},
      {'t': at(11, 8), 'lat': 41.67, 'lng': 26.55, 'acc': 8, 'spd': 0},
    ]);
    expect(computeActivity(dir.path, [key])[key]!.active, const Duration(minutes: 13));
  });

  test('periods', () {
    final now = DateTime(2026, 11, 5, 18); // Thursday
    expect(periodDays(Period.day, now), ['2026-11-05']);
    expect(periodDays(Period.week, now), ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05']);
    expect(periodDays(Period.month, now).length, 5);
  });
}
