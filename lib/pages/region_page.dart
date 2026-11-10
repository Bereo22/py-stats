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

/// Where a new customer is found quickly after a drop-off.
class RegionPage extends StatefulWidget {
  final String logDir;
  const RegionPage({super.key, required this.logDir});

  @override
  State<RegionPage> createState() => _RegionPageState();
}

class _RegionPageState extends State<RegionPage> {
  static const _grid = Grid(600);
  static const _slow = Color(0xFFD9534F);
  final _map = MapController();
  Period _period = Period.month;
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

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final turns = days == null ? const <Turnaround>[] : days.expand((d) => d.turnarounds).toList();
    final regions = groupByCell(_grid, turns, (t) => (t.drop.lat, t.drop.lng)).map(RegionStat.new).toList()
      ..sort((a, b) {
        final x = a.avgToRide, y = b.avgToRide;
        if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
        return x.compareTo(y);
      });
    final waits = regions.map((r) => r.avgToRide).whereType<Duration>().map((d) => d.inSeconds);
    final fastest = waits.isEmpty ? 0 : waits.reduce((a, b) => a < b ? a : b);
    final slowest = waits.isEmpty ? 0 : waits.reduce((a, b) => a > b ? a : b);

    Color color(RegionStat r) {
      final w = r.avgToRide;
      if (w == null) return Colors.grey.withValues(alpha: 0.45);
      final t = slowest == fastest ? 0.0 : (w.inSeconds - fastest) / (slowest - fastest);
      return Color.lerp(kGreen, _slow, t)!.withValues(alpha: 0.6);
    }

    final all = RegionStat(Cell(const CellKey(0, 0, 0))..items.addAll(turns));

    return Scaffold(
      appBar: AppBar(title: const Text('Bölge analizi')),
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
            Expanded(
              flex: 3,
              child: days == null
                  ? loading
                  : MapOrEmpty(
                      empty: turns.isEmpty,
                      emptyText: 'Bu dönemde tamamlanan yolculuk yok.\n'
                          'Müşteriyi bıraktıktan sonra yeni müşteriyi ne kadar sürede bulduğun burada bölge bölge görünecek.',
                      map: TagMap(
                        key: ValueKey('$_period ${turns.length}'),
                        controller: _map,
                        grid: _grid,
                        dots: [for (final t in turns) t.drop],
                        cells: [for (final r in regions) MapCell(r.cell.key, color(r), selected: r.cell.key == _selected)],
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: ListView(
                children: [
                  if (turns.isNotEmpty) ...[
                    StatRow('Bırakış', '${all.drops}'),
                    StatRow('Ortalama yeni müşteri süresi', _mins(all.avgToRide)),
                    StatRow('Ortalama ilk teklif süresi', _mins(all.avgToOffer)),
                    StatRow('Yeni müşteriye kadar boş yol (ort.)',
                        all.avgEmptyKm == null ? '-' : km(all.avgEmptyKm)),
                    if (all.unanswered > 0) StatRow('Sonra yolculuk gelmeden bitirdiğin', '${all.unanswered}'),
                    const SectionTitle('Bölgeler (en hızlıdan yavaşa)'),
                  ],
                  for (final (i, r) in regions.indexed) _regionTile(i, r, color(r)),
                  const Note('Her yolculuğun bittiği yerden, uygulama açıkken bir sonraki yolculuğu kabul edene kadar geçen süre. '
                      'Kareler yaklaşık 600 m. Yeşil hızlı, kırmızı yavaş; gri karelerde sonrasında yolculuk gelmeden bitirmişsin. '
                      'Güvenilir olması için bir bölgede en az 3-4 bırakış olmalı.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _mins(Duration? d) {
    if (d == null) return '-';
    if (d.inMinutes < 1) return '${d.inSeconds} sn';
    return d.inHours > 0 ? duration(d) : '${d.inMinutes} dk';
  }

  Widget _regionTile(int i, RegionStat r, Color color) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      selected: r.cell.key == _selected,
      selectedColor: kWhite,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 1),
        child: Text(r.avgToRide == null ? '-' : '${r.avgToRide!.inMinutes}', style: const TextStyle(color: kDark, fontWeight: FontWeight.w700)),
      ),
      title: Text(r.label ?? 'Bölge ${i + 1}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          '${r.drops} bırakış',
          if (r.avgToRide != null) 'yeni müşteri ${_mins(r.avgToRide)}',
          if (r.avgToOffer != null) 'ilk teklif ${_mins(r.avgToOffer)}',
          if (r.avgEmptyKm != null) 'boş ${km(r.avgEmptyKm)}',
          if (r.unanswered > 0) '${r.unanswered} kez yolculuk gelmedi',
          if (r.drops < 3) 'az veri',
        ].join(' · '),
        style: const TextStyle(color: kMuted),
      ),
      onTap: () {
        final (lat, lng) = _grid.center(r.cell.key);
        setState(() => _selected = r.cell.key);
        _map.move(LatLng(lat, lng), 15);
      },
    );
  }
}
