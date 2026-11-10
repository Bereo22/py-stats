import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/activity.dart';
import '../data/day_stats.dart';
import '../format.dart';
import '../parsing/trip_parser.dart';
import '../theme.dart';
import 'map_view.dart';
import 'widgets.dart';

/// One ride: its GPS route on a map and the numbers.
class TripPage extends StatefulWidget {
  final String logDir;
  final TripStat stat;
  const TripPage({super.key, required this.logDir, required this.stat});

  @override
  State<TripPage> createState() => _TripPageState();
}

class _TripPageState extends State<TripPage> {
  List<GpsPoint>? _gps;

  Trip get _trip => widget.stat.trip;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final from = _trip.acceptedAt.subtract(const Duration(seconds: 30)).millisecondsSinceEpoch;
    final to = (_trip.endedAt ?? _trip.lastSeen).add(const Duration(seconds: 30)).millisecondsSinceEpoch;
    List<GpsPoint> gps;
    try {
      gps = await loadRoute(widget.logDir, from, to);
    } catch (_) {
      gps = const [];
    }
    if (mounted) setState(() => _gps = gps);
  }

  @override
  Widget build(BuildContext context) {
    final t = _trip;
    final s = widget.stat;
    final gps = _gps;
    final started = t.startedAt?.millisecondsSinceEpoch;
    LatLng ll(GpsPoint p) => LatLng(p.lat, p.lng);
    final toPickup = gps == null
        ? <LatLng>[]
        : [for (final p in gps) if (started == null || p.t <= started) ll(p)];
    final ride = gps == null || started == null ? <LatLng>[] : [for (final p in gps) if (p.t >= started) ll(p)];

    return Scaffold(
      appBar: AppBar(title: Text('${t.acceptedAt.day}.${two(t.acceptedAt.month)} · ${hhmm(t.acceptedAt)} yolculuğu')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.5,
            child: gps == null
                ? loading
                : MapOrEmpty(
                    empty: gps.isEmpty && s.pickupPoint == null,
                    emptyText: 'Bu yolculuk sırasında GPS kaydı yok.',
                    map: RouteMap(
                      toPickup: toPickup,
                      ride: ride,
                      acceptedAt: toPickup.isEmpty ? null : toPickup.first,
                      pickup: s.pickupPoint == null ? null : ll(s.pickupPoint!),
                      dropoff: s.dropoffPoint == null ? null : ll(s.dropoffPoint!),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Legend(),
                const SizedBox(height: 12),
                SummaryCard(
                  label: t.customerKey,
                  value: t.canceled ? (t.canceledBy ?? CancelBy.unknown).label : money(t.price),
                  rows: [
                    StatRow('Kabul', hhmm(t.acceptedAt)),
                    if (t.startedAt != null) StatRow('Müşteri bindi', hhmm(t.startedAt!)),
                    if (t.endedAt != null) StatRow('Müşteri indi', hhmm(t.endedAt!)),
                    StatRow('Müşteriye gidiş', '${km(s.pickupKm)} · ${s.pickupTime.inMinutes} dk'),
                    if (!t.canceled) StatRow('Yolculuk', '${km(s.rideKm)} · ${s.rideTime.inMinutes} dk'),
                    if (t.price != null && s.pickupKm + s.rideKm > 0 && !t.canceled)
                      StatRow('TL/km (gidiş dahil)', (t.price! / (s.pickupKm + s.rideKm)).toStringAsFixed(1)),
                    if (t.payment != null) StatRow('Ödeme', t.payment!),
                    if (t.pickupAddress != null) StatRow('Alış', t.pickupAddress!),
                    if (t.dropoffAddress != null) StatRow('Bırakış', t.dropoffAddress!),
                    if (t.estTripKm != null)
                      StatRow('Martı tahmini', '${km(t.estPickupKm)} + ${km(t.estTripKm)}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Widget mark, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [mark, const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 12))],
        );
    Widget line(Color c, {bool dashed = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < (dashed ? 3 : 1); i++)
              Container(
                width: dashed ? 6 : 22,
                height: 4,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(color: c, border: dashed ? null : Border.all(color: kDark, width: 0.5)),
              ),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(line(kBox, dashed: true), 'Müşteriye gidiş'),
        item(line(kGreen), 'Müşteriyle'),
        item(const Icon(Icons.person, size: 16, color: kGreen), 'Alış'),
        item(const Icon(Icons.flag, size: 16, color: kWhite), 'Bırakış'),
      ],
    );
  }
}
