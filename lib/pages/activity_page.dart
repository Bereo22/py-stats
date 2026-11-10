import 'package:flutter/material.dart';

import '../data/day_stats.dart';
import '../data/periods.dart';
import '../format.dart';
import 'widgets.dart';

enum ActivityFocus { distance, time }

class ActivityPage extends StatefulWidget {
  final String logDir;
  final ActivityFocus focus;
  final bool tracking;
  const ActivityPage({super.key, required this.logDir, required this.focus, this.tracking = false});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  Period _period = Period.day;
  List<DayStats>? _days;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _days = null);
    final keys = periodDays(_period);
    final map = await loadDayStats(widget.logDir, keys, openUntil: widget.tracking ? DateTime.now() : null);
    if (mounted) setState(() => _days = [for (final k in keys) map[k]!]);
  }

  @override
  Widget build(BuildContext context) {
    final isDistance = widget.focus == ActivityFocus.distance;
    final days = _days;
    return Scaffold(
      appBar: AppBar(title: Text(isDistance ? 'Yol' : 'Aktif süre')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          PeriodPicker(
            value: _period,
            onChanged: (p) {
              _period = p;
              _load();
            },
          ),
          const SizedBox(height: 16),
          if (days == null) loading else ..._content(days, isDistance),
        ],
      ),
    );
  }

  List<Widget> _content(List<DayStats> days, bool isDistance) {
    final t = Totals(days);
    final byDay = {for (final d in days) d.day: Totals([d])};
    final hours = t.active.inMinutes / 60;
    String share(double part, double whole) => whole <= 0 ? '' : ' (%${(part / whole * 100).round()})';
    String shareD(Duration part, Duration whole) => share(part.inSeconds.toDouble(), whole.inSeconds.toDouble());
    final worked = t.workedDays;

    return [
      if (isDistance)
        SummaryCard(
          label: 'Toplam yol',
          value: km(t.km),
          rows: [
            StatRow('Müşteriyle', '${km(t.rideKm)}${share(t.rideKm, t.km)}'),
            StatRow('Müşteriye giderken', '${km(t.pickupKm)}${share(t.pickupKm, t.km)}'),
            StatRow('Boş (müşterisiz)', '${km(t.emptyKm)}${share(t.emptyKm, t.km)}'),
            StatRow('Aktif süre', duration(t.active)),
            StatRow('Ortalama hız (aktifken)', hours > 0 ? '${(t.km / hours).toStringAsFixed(1)} km/sa' : '-'),
            if (days.length > 1) ...[
              StatRow('Çalışılan gün', '$worked'),
              StatRow('Gün başına yol', worked == 0 ? '-' : km(t.km / worked)),
            ],
          ],
        )
      else
        SummaryCard(
          label: 'Toplam aktif süre',
          value: duration(t.active),
          rows: [
            StatRow('Müşteriyle', '${duration(t.rideTime)}${shareD(t.rideTime, t.active)}'),
            StatRow('Müşteriye giderken', '${duration(t.pickupTime)}${shareD(t.pickupTime, t.active)}'),
            StatRow('Müşterisiz (bekleme, arama)', '${duration(t.idleTime)}${shareD(t.idleTime, t.active)}'),
            StatRow('Yol', km(t.km)),
            if (days.length > 1) ...[
              StatRow('Çalışılan gün', '$worked'),
              StatRow('Gün başına süre',
                  worked == 0 ? '-' : duration(Duration(minutes: t.active.inMinutes ~/ worked))),
            ],
          ],
        ),
      if (days.length > 1) ...[
        const SectionTitle('Günlere göre'),
        DayBars(
          days: [for (final d in days) d.day],
          value: (d) => isDistance ? byDay[d]!.km : byDay[d]!.active.inMinutes.toDouble(),
          label: (d) => isDistance ? km(byDay[d]!.km) : duration(byDay[d]!.active),
        ),
      ],
      const Note('Müşteriyle: yolculuk başladıktan bitene kadar. Müşteriye giderken: teklifi kabul ettikten '
          'müşteri binene kadar. Boş: geri kalan her şey. Mesafeler GPS kaydından ölçülür.'),
    ];
  }
}
