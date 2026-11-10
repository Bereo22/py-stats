import 'package:flutter/material.dart';

import '../data/day_stats.dart';
import '../data/periods.dart';
import '../format.dart';
import '../parsing/trip_parser.dart';
import '../theme.dart';
import 'trip_page.dart';
import 'widgets.dart';

class EarningsPage extends StatefulWidget {
  final String logDir;
  final bool tracking;
  const EarningsPage({super.key, required this.logDir, required this.tracking});

  @override
  State<EarningsPage> createState() => _EarningsPageState();
}

class _EarningsPageState extends State<EarningsPage> {
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
    final days = _days;
    return Scaffold(
      appBar: AppBar(title: const Text('Kazanç')),
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
          if (days == null) loading else ..._content(days),
        ],
      ),
    );
  }

  List<Widget> _content(List<DayStats> days) {
    final t = Totals(days);
    final byDay = {for (final d in days) d.day: Totals([d])};
    final trips = days.expand((d) => d.trips).toList().reversed.toList();
    return [
      SummaryCard(
        label: 'Toplam kazanç',
        value: money(t.earnings),
        rows: [
          StatRow('Yolculuk', '${t.tripCount}'),
          StatRow('Yolculuk başı', money(t.perTrip?.roundToDouble())),
          StatRow('Saatlik (aktif süreye göre)', t.perHour == null ? '-' : '${money(t.perHour!.roundToDouble())}/sa'),
          StatRow('Km başı (toplam yola göre)', t.perKm == null ? '-' : '${t.perKm!.toStringAsFixed(1)} TL/km'),
          StatRow('Nakit', money(t.earningsBy('Nakit'))),
          StatRow('Kart', money(t.earningsBy('Kart'))),
          StatRow('Gelen teklif', '${t.offerCount}'),
          if (t.acceptRate != null) StatRow('Kabul oranı', '%${(t.acceptRate! * 100).round()}'),
          if (t.canceledCount > 0)
            StatRow(
              'Kabul sonrası iptal',
              '${t.canceledCount} (sen ${t.canceledBy(CancelBy.driver)}, yolcu ${t.canceledBy(CancelBy.customer)})',
            ),
        ],
      ),
      if (days.length > 1) ...[
        const SectionTitle('Günlere göre'),
        DayBars(
          days: [for (final d in days) d.day],
          value: (d) => byDay[d]!.earnings,
          label: (d) => money(byDay[d]!.earnings),
        ),
      ],
      const SectionTitle('Yolculuklar'),
      if (trips.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bu dönemde yolculuk algılanmadı. Başlat\'a basıp ekran okumayı açık tutarak çalıştıkça burası dolacak.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kMuted),
          ),
        ),
      for (final s in trips)
        _TripCard(
          s,
          showDate: days.length > 1,
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => TripPage(logDir: widget.logDir, stat: s))),
        ),
      const Note('Kazanç, yolculuk ekranında okunan ücretten hesaplanır. '
          'Müşteriye gidiş ve yolculuk km\'si telefonun GPS kaydından ölçülür.'),
    ];
  }
}

class _TripCard extends StatelessWidget {
  final TripStat s;
  final bool showDate;
  final VoidCallback onTap;
  const _TripCard(this.s, {required this.showDate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = s.trip;
    final end = t.endedAt;
    final when = [
      if (showDate) '${t.acceptedAt.day}.${two(t.acceptedAt.month)}',
      '${hhmm(t.acceptedAt)}–${end == null ? (t.canceled ? hhmm(t.lastSeen) : 'devam ediyor') : hhmm(end)}',
    ].join(' ');
    return Box(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(when, style: const TextStyle(color: kBoxMuted)),
                const SizedBox(width: 8),
                if (t.customerInitials != null) Flexible(child: Text(t.customerKey, overflow: TextOverflow.ellipsis)),
                const Spacer(),
                Text(
                  t.canceled ? (t.canceledBy ?? CancelBy.unknown).label : money(t.price),
                  style: TextStyle(
                    fontSize: t.canceled ? 14 : 20,
                    fontWeight: FontWeight.w700,
                    color: t.canceled ? kBoxMuted : kDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _leg(Icons.person_pin_circle, kBoxMuted, 'Müşteriye', s.pickupKm, s.pickupTime, t.pickupAddress),
            if (!t.canceled) ...[
              const SizedBox(height: 4),
              _leg(Icons.place, kDark, 'Yolculuk', s.rideKm, s.rideTime, t.dropoffAddress),
            ],
            if (t.payment != null || t.estTripKm != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (t.payment != null) t.payment!,
                  if (t.price != null && s.pickupKm + s.rideKm > 0)
                    '${(t.price! / (s.pickupKm + s.rideKm)).toStringAsFixed(1)} TL/km',
                  if (t.estTripKm != null) 'Martı tahmini ${km(t.estPickupKm)} + ${km(t.estTripKm)}',
                ].join(' · '),
                style: const TextStyle(color: kBoxMuted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _leg(IconData icon, Color color, String title, double distance, Duration time, String? address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text('$title: ${km(distance)} · ${time.inMinutes} dk${address == null ? '' : '\n$address'}'),
        ),
      ],
    );
  }
}
