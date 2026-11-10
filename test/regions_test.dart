import 'package:flutter_test/flutter_test.dart';
import 'package:tag_stats/data/activity.dart';
import 'package:tag_stats/data/day_stats.dart';
import 'package:tag_stats/data/regions.dart';
import 'package:tag_stats/parsing/offer_parser.dart';
import 'package:tag_stats/parsing/trip_parser.dart';

DateTime at(int h, int m) => DateTime(2026, 11, 7, h, m);
int ms(int h, int m) => at(h, m).millisecondsSinceEpoch;

TripStat ride(int h, int m, {required int endH, required int endM, required double lat}) {
  final t = Trip(at(h, m))
    ..startedAt = at(h, m + 3)
    ..endedAt = at(endH, endM)
    ..dropoffAddress = 'EDIRNE MERKEZ, Selimiye Cami';
  return TripStat(t, 1, 3, GpsPoint(ms(h, m + 3), lat, 26.55, 5, 0), GpsPoint(ms(endH, endM), lat, 26.56, 5, 0));
}

void main() {
  test('grid puts nearby points in one cell and far points apart', () {
    const g = Grid(400);
    expect(g.keyOf(41.6771, 26.5557), g.keyOf(41.6772, 26.5558));
    expect(g.keyOf(41.6771, 26.5557) == g.keyOf(41.6871, 26.5557), isFalse);
    final (lat, lng) = g.center(g.keyOf(41.6771, 26.5557));
    expect(lat, closeTo(41.6771, 0.004));
    expect(lng, closeTo(26.5557, 0.005));
  });

  test('turnarounds measure time to next offer and ride within the session', () {
    final first = ride(10, 0, endH: 10, endM: 20, lat: 41.67);
    final second = ride(10, 32, endH: 10, endM: 50, lat: 41.68);
    final offer = Offer(firstSeen: at(10, 25), src: 'ocr');
    final gps = [
      GpsPoint(ms(10, 20), 41.670, 26.55, 5, 8),
      GpsPoint(ms(10, 26), 41.675, 26.55, 5, 8),
      GpsPoint(ms(10, 32), 41.680, 26.55, 5, 8),
    ];
    final turns = turnarounds([first, second], [offer], [(ms(9, 0), ms(11, 0))], gps);

    expect(turns, hasLength(2));
    expect(turns[0].toOffer, const Duration(minutes: 5));
    expect(turns[0].toRide, const Duration(minutes: 12));
    expect(turns[0].emptyKm, closeTo(1.11, 0.05));
    expect(turns[1].toRide, isNull);
    expect(turns[1].unansweredWait, const Duration(minutes: 10));

    final region = RegionStat(groupByCell(const Grid(600), turns.take(1), (t) => (t.drop.lat, t.drop.lng)).single);
    expect(region.label, 'Selimiye Cami');
    expect(region.avgToRide, const Duration(minutes: 12));
  });
}
