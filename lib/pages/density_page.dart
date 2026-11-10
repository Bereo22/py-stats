import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/day_stats.dart';
import '../data/periods.dart';
import '../data/regions.dart';
import '../format.dart';
import '../theme.dart';
import 'map_view.dart';
import 'widgets.dart';

enum DensityLayer { pickup, dropoff, offers }

extension on DensityLayer {
  String get label => switch (this) {
        DensityLayer.pickup => 'Alış',
        DensityLayer.dropoff => 'Bırakış',
        DensityLayer.offers => 'Teklif geldiğinde',
      };

  String get unit => switch (this) {
        DensityLayer.pickup => 'alış',
        DensityLayer.dropoff => 'bırakış',
        DensityLayer.offers => 'teklif',
      };
}

class DensityPage extends StatefulWidget {
  final String logDir;
  const DensityPage({super.key, required this.logDir});

  @override
  State<DensityPage> createState() => _DensityPageState();
}

class _DensityPageState extends State<DensityPage> {
  static const _grid = Grid(400);
  final _map = MapController();
  Period _period = Period.month;
  DensityLayer _layer = DensityLayer.pickup;
  List<DayStats>? _days;
  CellKey? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _days = null);
    final map = await loadDayStats(widget.logDir, periodDays(_period));
    if (mounted) setState(() => _days = map.values.toList());
  }

  List<Spot> _spots(List<DayStats> days) {
    final trips = days.expand((d) => d.paid);
    return switch (_layer) {
      DensityLayer.pickup => [
          for (final s in trips)
            if (s.pickupPoint != null)
              Spot(s.pickupPoint!.lat, s.pickupPoint!.lng, s.trip.startedAt!,
                  label: s.trip.pickupAddress, price: s.trip.price),
        ],
      DensityLayer.dropoff => [
          for (final s in trips)
            if (s.dropoffPoint != null)
              Spot(s.dropoffPoint!.lat, s.dropoffPoint!.lng, s.trip.endedAt!,
                  label: s.trip.dropoffAddress, price: s.trip.price),
        ],
      DensityLayer.offers => [
          for (final o in days.expand((d) => d.offers))
            if (o.lat != null && o.lng != null) Spot(o.lat!, o.lng!, o.firstSeen, price: o.price),
        ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final spots = days == null ? const <Spot>[] : _spots(days);
    final cells = groupByCell(_grid, spots, (s) => (s.lat, s.lng));
    final maxCount = cells.isEmpty ? 1 : cells.first.items.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Yoğunluk haritası')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PeriodPicker(
              value: _period,
              onChanged: (p) {
                _period = p;
                _selected = null;
                _load();
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final l in DensityLayer.values)
                  ChoiceChip(
                    label: Text(l.label),
                    selected: _layer == l,
                    selectedColor: kGreen,
                    checkmarkColor: kDark,
                    labelStyle: TextStyle(color: _layer == l ? kDark : kWhite),
                    onSelected: (_) => setState(() {
                      _layer = l;
                      _selected = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: days == null
                  ? loading
                  : MapOrEmpty(
                      empty: spots.isEmpty,
                      emptyText: 'Bu dönemde ${_layer.unit} noktası yok.',
                      map: TagMap(
                        key: ValueKey('$_period $_layer ${spots.length}'),
                        controller: _map,
                        grid: _grid,
                        dots: spots,
                        cells: [
                          for (final c in cells)
                            MapCell(
                              c.key,
                              Color.lerp(kGreen.withValues(alpha: 0.2), kGreen.withValues(alpha: 0.75),
                                  c.items.length / maxCount)!,
                              selected: c.key == _selected,
                            ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: ListView(
                children: [
                  Text(
                    '${spots.length} ${_layer.unit} · ${cells.length} bölge (yaklaşık ${_grid.sizeM.round()} m kareler)',
                    style: const TextStyle(color: kMuted),
                  ),
                  for (final (i, c) in cells.take(10).indexed) _cellTile(i, c),
                  Note(switch (_layer) {
                    DensityLayer.pickup => 'Müşterinin bindiği yer: yolculuğun başladığı andaki GPS konumu.',
                    DensityLayer.dropoff => 'Müşterinin indiği yer: yolculuğun bittiği andaki GPS konumu.',
                    DensityLayer.offers => 'Teklif ekrana geldiğinde senin bulunduğun yer. '
                        'Nerede beklersen daha çok teklif geldiğini gösterir.',
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cellTile(int i, Cell<Spot> c) {
    final label = commonLabel(c.items.map((s) => s.label)) ?? 'Bölge ${i + 1}';
    final prices = c.items.map((s) => s.price).whereType<double>().toList();
    final avg = prices.isEmpty ? null : prices.reduce((a, b) => a + b) / prices.length;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      selected: c.key == _selected,
      selectedColor: kWhite,
      leading: CircleAvatar(
        backgroundColor: kGreen,
        child: Text('${c.items.length}', style: const TextStyle(color: kDark, fontWeight: FontWeight.w700)),
      ),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          '${c.items.length} ${_layer.unit}',
          if (avg != null) 'ort. ${money(avg.roundToDouble())}',
        ].join(' · '),
        style: const TextStyle(color: kMuted),
      ),
      onTap: () {
        final (lat, lng) = _grid.center(c.key);
        setState(() => _selected = c.key);
        _map.move(LatLng(lat, lng), 15.5);
      },
    );
  }
}
