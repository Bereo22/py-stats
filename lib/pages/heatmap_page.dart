import 'dart:math';

import 'package:flutter/material.dart';

import '../data/day_stats.dart';
import '../data/log_reader.dart';
import '../data/periods.dart';
import '../theme.dart';
import 'widgets.dart';

enum HeatMetric { perHour, earnings, offers, offerPerKm }

extension on HeatMetric {
  String get label => switch (this) {
        HeatMetric.perHour => 'TL/saat',
        HeatMetric.earnings => 'Kazanç',
        HeatMetric.offers => 'Teklif sayısı',
        HeatMetric.offerPerKm => 'Teklif TL/km',
      };
}

/// Weekday × hour grid over the last weeks.
class HeatmapPage extends StatefulWidget {
  final String logDir;
  const HeatmapPage({super.key, required this.logDir});

  @override
  State<HeatmapPage> createState() => _HeatmapPageState();
}

class _HeatmapPageState extends State<HeatmapPage> {
  static const _lookbackDays = 28;

  /// Hours with less active time than this are too noisy for TL/saat.
  static const _minActive = Duration(minutes: 10);

  HeatMetric _metric = HeatMetric.perHour;
  List<DayStats>? _days;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cutoff = dayKey(DateTime.now().subtract(const Duration(days: _lookbackDays - 1)));
    final keys = (await LogReader(widget.logDir).days()).where((d) => d.compareTo(cutoff) >= 0).toList();
    final map = await loadDayStats(widget.logDir, keys);
    if (mounted) setState(() => _days = map.values.toList());
  }

  /// cells[weekday 0..6][hour 0..23] -> value, or null when there is no data.
  List<List<double?>> _cells(List<DayStats> days) {
    final earn = List.generate(7, (_) => List.filled(24, 0.0));
    final activeMs = List.generate(7, (_) => List.filled(24, 0));
    final offerCount = List.generate(7, (_) => List.filled(24, 0));
    final perKm = List.generate(7, (_) => List.generate(24, (_) => <double>[]));

    for (final d in days) {
      for (final s in d.paid) {
        final at = s.trip.startedAt!;
        earn[at.weekday - 1][at.hour] += s.trip.price ?? 0;
      }
      for (final o in d.offers) {
        offerCount[o.firstSeen.weekday - 1][o.firstSeen.hour]++;
        if (o.tlPerKm != null) perKm[o.firstSeen.weekday - 1][o.firstSeen.hour].add(o.tlPerKm!);
      }
      for (final (from, to) in d.activity.intervals) {
        var t = from;
        while (t < to) {
          final dt = DateTime.fromMillisecondsSinceEpoch(t);
          final hourEnd = DateTime(dt.year, dt.month, dt.day, dt.hour + 1).millisecondsSinceEpoch;
          final end = min(hourEnd, to);
          activeMs[dt.weekday - 1][dt.hour] += end - t;
          t = end;
        }
      }
    }

    return [
      for (var w = 0; w < 7; w++)
        [
          for (var h = 0; h < 24; h++)
            switch (_metric) {
              HeatMetric.perHour => activeMs[w][h] < _minActive.inMilliseconds
                  ? null
                  : earn[w][h] / (activeMs[w][h] / 3600000),
              HeatMetric.earnings => earn[w][h] == 0 ? null : earn[w][h],
              HeatMetric.offers => offerCount[w][h] == 0 ? null : offerCount[w][h].toDouble(),
              HeatMetric.offerPerKm =>
                perKm[w][h].isEmpty ? null : perKm[w][h].reduce((a, b) => a + b) / perKm[w][h].length,
            }
        ]
    ];
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final t = days == null ? null : Totals(days);
    return Scaffold(
      appBar: AppBar(title: const Text('Isı haritası')),
      body: days == null
          ? loading
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in HeatMetric.values)
                      ChoiceChip(
                        label: Text(m.label),
                        selected: _metric == m,
                        selectedColor: kGreen,
                        checkmarkColor: kDark,
                        labelStyle: TextStyle(color: _metric == m ? kDark : kWhite),
                        onSelected: (_) => setState(() => _metric = m),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Son $_lookbackDays gün · ${days.length} günlük kayıt · ${t!.tripCount} yolculuk · ${t.offerCount} teklif',
                  style: const TextStyle(color: kMuted),
                ),
                const SizedBox(height: 12),
                _Grid(cells: _cells(days), metric: _metric),
                Note(switch (_metric) {
                  HeatMetric.perHour => 'TL/saat: o gün ve saatte kazanılan para, o saatte uygulama açıkken geçen süreye bölünür. '
                      '${_minActive.inMinutes} dakikadan az çalışılan saatler boş bırakılır. Yolculuğun ücreti başladığı saate yazılır.',
                  HeatMetric.earnings => 'Son $_lookbackDays günde o gün ve saatte başlayan yolculukların toplam ücreti.',
                  HeatMetric.offers => 'O gün ve saatte gelen teklif sayısı.',
                  HeatMetric.offerPerKm => 'Tekliflerin ortalama TL/km değeri (müşteriye gidiş + yolculuk km\'si).',
                }),
              ],
            ),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<List<double?>> cells;
  final HeatMetric metric;
  const _Grid({required this.cells, required this.metric});

  static const _cell = 30.0;
  static const _gap = 2.0;

  String _fmt(double v) => v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final values = cells.expand((r) => r).whereType<double>();
    final maxV = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final minV = values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);

    Color color(double? v) {
      if (v == null) return const Color(0x26FFFFFF);
      final t = maxV == minV ? 1.0 : (v - minV) / (maxV - minV);
      return Color.lerp(const Color(0xFF9BA88A), kGreen, t)!;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 36),
              for (var h = 0; h < 24; h++)
                Container(
                  width: _cell,
                  margin: const EdgeInsets.all(_gap / 2),
                  alignment: Alignment.center,
                  child: Text(h.toString().padLeft(2, '0'), style: const TextStyle(color: kMuted, fontSize: 10)),
                ),
            ],
          ),
          for (var d = 0; d < 7; d++)
            Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(weekdayShort[d], style: const TextStyle(color: kMuted, fontSize: 12)),
                ),
                for (var h = 0; h < 24; h++)
                  Tooltip(
                    message: cells[d][h] == null
                        ? '${weekdayShort[d]} ${h.toString().padLeft(2, '0')}:00 · veri yok'
                        : '${weekdayShort[d]} ${h.toString().padLeft(2, '0')}:00 · ${metric.label}: ${_fmt(cells[d][h]!)}',
                    triggerMode: TooltipTriggerMode.tap,
                    child: Container(
                      width: _cell,
                      height: _cell,
                      margin: const EdgeInsets.all(_gap / 2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: color(cells[d][h]), borderRadius: BorderRadius.circular(5)),
                      child: cells[d][h] == null
                          ? null
                          : Text(_fmt(cells[d][h]!), style: const TextStyle(fontSize: 10, color: kDark, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
