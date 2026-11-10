import '../format.dart';

enum Period { day, week, month }

extension PeriodLabel on Period {
  String get label => switch (this) {
        Period.day => 'Bugün',
        Period.week => 'Bu hafta',
        Period.month => 'Bu ay',
      };
}

String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

DateTime parseDayKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Day keys from the start of the period up to and including [now]'s day.
List<String> periodDays(Period period, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final start = switch (period) {
    Period.day => DateTime(today.year, today.month, today.day),
    Period.week => DateTime(today.year, today.month, today.day - (today.weekday - 1)),
    Period.month => DateTime(today.year, today.month, 1),
  };
  final days = <String>[];
  for (var d = start; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1)) {
    days.add(dayKey(d));
  }
  return days;
}

const weekdayShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

String duration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m dk';
  return '$h sa ${two(m)} dk';
}
