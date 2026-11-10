import 'dart:math';

/// Square grid over the map; [sizeM] is the cell edge in meters.
class Grid {
  final double sizeM;
  const Grid(this.sizeM);

  static const _mPerDegLat = 111320.0;

  /// Longitude step uses a fixed latitude so cells line up across the whole map.
  double get _latStep => sizeM / _mPerDegLat;
  double _lngStep(double lat) => sizeM / (_mPerDegLat * cos(lat.roundToDouble() * pi / 180));

  CellKey keyOf(double lat, double lng) =>
      CellKey((lat / _latStep).floor(), (lng / _lngStep(lat)).floor(), lat.roundToDouble());

  /// South-west and north-east corners.
  ((double, double), (double, double)) bounds(CellKey k) {
    final lngStep = _lngStep(k.refLat);
    return ((k.row * _latStep, k.col * lngStep), ((k.row + 1) * _latStep, (k.col + 1) * lngStep));
  }

  (double, double) center(CellKey k) {
    final ((s, w), (n, e)) = bounds(k);
    return ((s + n) / 2, (w + e) / 2);
  }
}

class CellKey {
  final int row;
  final int col;
  final double refLat;
  const CellKey(this.row, this.col, this.refLat);

  @override
  bool operator ==(Object other) => other is CellKey && other.row == row && other.col == col && other.refLat == refLat;

  @override
  int get hashCode => Object.hash(row, col, refLat);
}

/// A point on the map with an optional address label and fare.
class Spot {
  final double lat;
  final double lng;
  final DateTime time;
  final String? label;
  final double? price;
  const Spot(this.lat, this.lng, this.time, {this.label, this.price});
}

class Cell<T> {
  final CellKey key;
  final List<T> items = [];
  Cell(this.key);
}

List<Cell<T>> groupByCell<T>(Grid grid, Iterable<T> items, (double, double) Function(T) pos) {
  final map = <CellKey, Cell<T>>{};
  for (final it in items) {
    final (lat, lng) = pos(it);
    final k = grid.keyOf(lat, lng);
    map.putIfAbsent(k, () => Cell(k)).items.add(it);
  }
  return map.values.toList()..sort((a, b) => b.items.length.compareTo(a.items.length));
}

/// "EDIRNE MERKEZ, Selimiye Cami" -> "Selimiye Cami"; the most frequent wins.
String? commonLabel(Iterable<String?> labels) {
  final counts = <String, int>{};
  for (final l in labels) {
    if (l == null) continue;
    final short = l.replaceFirst(RegExp(r'^[^,]*MERKEZ,\s*', caseSensitive: false), '').trim();
    if (short.isEmpty) continue;
    counts[short] = (counts[short] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// What happened after dropping a customer off.
class Turnaround {
  final Spot drop;

  /// Next offer seen after the drop, if any before the session ended.
  final Duration? toOffer;

  /// Next ride that actually started (its acceptance time).
  final Duration? toRide;

  /// GPS km driven empty from the drop to the next ride's acceptance.
  final double? emptyKm;

  /// The session ended (or the day did) before another ride; how long that wait lasted.
  final Duration? unansweredWait;

  final double? nextPrice;

  const Turnaround(this.drop,
      {this.toOffer, this.toRide, this.emptyKm, this.unansweredWait, this.nextPrice});
}

class RegionStat {
  final Cell<Turnaround> cell;
  final String? label;
  RegionStat(this.cell) : label = commonLabel(cell.items.map((t) => t.drop.label));

  List<Turnaround> get _found => cell.items.where((t) => t.toRide != null).toList();
  int get drops => cell.items.length;
  int get found => _found.length;
  int get unanswered => cell.items.where((t) => t.toRide == null).length;

  Duration? get avgToRide => _avg(_found.map((t) => t.toRide!));
  Duration? get avgToOffer => _avg(cell.items.map((t) => t.toOffer).whereType<Duration>());
  double? get avgEmptyKm {
    final xs = _found.map((t) => t.emptyKm).whereType<double>().toList();
    return xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;
  }

  static Duration? _avg(Iterable<Duration> ds) {
    final l = ds.toList();
    if (l.isEmpty) return null;
    return Duration(milliseconds: l.fold<int>(0, (s, d) => s + d.inMilliseconds) ~/ l.length);
  }
}
