import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import '../parsing/offer_parser.dart';
import '../parsing/trip_parser.dart';
import 'activity.dart';
import 'log_reader.dart';
import 'regions.dart';

class TripStat {
  final Trip trip;

  /// GPS km from acceptance to the customer getting in.
  final double pickupKm;

  /// GPS km with the customer on board.
  final double rideKm;
  final GpsPoint? pickupPoint;
  final GpsPoint? dropoffPoint;

  TripStat(this.trip, this.pickupKm, this.rideKm, this.pickupPoint, this.dropoffPoint);

  Duration get pickupTime => _span(trip.acceptedAt, trip.startedAt);
  Duration get rideTime => _span(trip.startedAt, trip.endedAt ?? trip.lastSeen);

  static Duration _span(DateTime? a, DateTime? b) =>
      a == null || b == null || b.isBefore(a) ? Duration.zero : b.difference(a);
}

class DayStats {
  final DayActivity activity;
  final List<TripStat> trips;
  final List<Offer> offers;
  final List<Turnaround> turnarounds;
  DayStats(this.activity, this.trips, this.offers, [this.turnarounds = const []]);

  String get day => activity.day;

  /// Started, not canceled rides.
  Iterable<TripStat> get paid => trips.where((t) => t.trip.paid);
}

/// Sums over any set of days.
class Totals {
  final List<DayStats> days;
  Totals(this.days);

  Iterable<TripStat> get _paid => days.expand((d) => d.paid);

  int get tripCount => _paid.length;
  int get offerCount => days.fold(0, (s, d) => s + d.offers.length);
  int get canceledCount => days.fold(0, (s, d) => s + d.trips.where((t) => t.trip.canceled).length);
  int canceledBy(CancelBy by) =>
      days.fold(0, (s, d) => s + d.trips.where((t) => t.trip.canceled && t.trip.canceledBy == by).length);
  double get earnings => _paid.fold(0, (s, t) => s + (t.trip.price ?? 0));
  double earningsBy(String payment) =>
      _paid.where((t) => t.trip.payment == payment).fold(0, (s, t) => s + (t.trip.price ?? 0));

  double get km => days.fold(0, (s, d) => s + d.activity.km);
  double get rideKm => _paid.fold(0, (s, t) => s + t.rideKm);
  double get pickupKm => _paid.fold(0, (s, t) => s + t.pickupKm);

  /// Driving around with no ride assigned.
  double get emptyKm => max(0, km - rideKm - pickupKm);

  Duration get active => days.fold(Duration.zero, (s, d) => s + d.activity.active);
  Duration get rideTime => _paid.fold(Duration.zero, (s, t) => s + t.rideTime);
  Duration get pickupTime => _paid.fold(Duration.zero, (s, t) => s + t.pickupTime);
  Duration get idleTime {
    final d = active - rideTime - pickupTime;
    return d.isNegative ? Duration.zero : d;
  }

  int get workedDays => days.where((d) => d.activity.active > Duration.zero || d.trips.isNotEmpty).length;

  double? get perHour => active.inMinutes < 1 ? null : earnings / (active.inMinutes / 60);
  double? get perKm => km <= 0 ? null : earnings / km;
  double? get perTrip => tripCount == 0 ? null : earnings / tripCount;

  /// Share of distance driven with a customer on board.
  double? get rideKmShare => km <= 0 ? null : min(1, rideKm / km);
  int get acceptedCount => days.fold(0, (s, d) => s + d.offers.where((o) => o.accepted).length);
  double? get acceptRate => offerCount == 0 ? null : acceptedCount / offerCount;
}

Future<Map<String, DayStats>> loadDayStats(String dir, List<String> days, {DateTime? openUntil}) {
  final until = openUntil?.millisecondsSinceEpoch;
  return Isolate.run(() => computeDayStats(dir, days, openUntilMs: until));
}

Map<String, DayStats> computeDayStats(String dir, List<String> days, {int? openUntilMs}) {
  final activity = computeActivity(dir, days, openUntilMs: openUntilMs);
  final out = <String, DayStats>{};
  for (final day in days) {
    final log = TripParser.parse(parseScreensFile('$dir${Platform.pathSeparator}screens_$day.jsonl'));
    final gps = log.trips.isEmpty ? const <GpsPoint>[] : readGps(dir, day);
    final trips = [for (final t in log.trips) tripStat(t, gps)];
    final act = activity[day] ?? DayActivity.empty(day);
    out[day] = DayStats(act, trips, log.offers, turnarounds(trips, log.offers, act.intervals, gps));
  }
  return out;
}

/// For every finished ride: how long until the next offer and the next ride, within the same session.
List<Turnaround> turnarounds(
    List<TripStat> trips, List<Offer> offers, List<(int, int)> intervals, List<GpsPoint> gps) {
  const tolerance = 2 * 60 * 1000;
  final starts = trips.where((t) => t.trip.paid).toList()
    ..sort((a, b) => a.trip.acceptedAt.compareTo(b.trip.acceptedAt));
  final out = <Turnaround>[];
  for (final s in trips) {
    final end = s.trip.endedAt;
    final p = s.dropoffPoint;
    if (!s.trip.completed || end == null || p == null) continue;
    final endMs = end.millisecondsSinceEpoch;
    final session = intervals.where((i) => i.$1 - tolerance <= endMs && endMs <= i.$2 + tolerance);
    final limit = session.isEmpty ? endMs : max(session.first.$2, endMs);

    bool inWindow(DateTime t) => t.isAfter(end) && t.millisecondsSinceEpoch <= limit;
    final next = starts.where((t) => inWindow(t.trip.acceptedAt)).firstOrNull;
    final offer = offers.where((o) => inWindow(o.firstSeen)).firstOrNull;
    final drop = Spot(p.lat, p.lng, end, label: s.trip.dropoffAddress, price: s.trip.price);
    final toOffer = offer?.firstSeen.difference(end);
    if (next == null) {
      out.add(Turnaround(drop, toOffer: toOffer, unansweredWait: Duration(milliseconds: limit - endMs)));
    } else {
      final accepted = next.trip.acceptedAt;
      out.add(Turnaround(
        drop,
        toOffer: toOffer,
        toRide: accepted.difference(end),
        emptyKm: distanceKm(gps, fromMs: endMs, toMs: accepted.millisecondsSinceEpoch),
        nextPrice: next.trip.price,
      ));
    }
  }
  return out;
}

TripStat tripStat(Trip t, List<GpsPoint> gps) {
  final accepted = t.acceptedAt.millisecondsSinceEpoch;
  final started = t.startedAt?.millisecondsSinceEpoch;
  final ended = (t.endedAt ?? t.lastSeen).millisecondsSinceEpoch;
  return TripStat(
    t,
    started == null ? distanceKm(gps, fromMs: accepted, toMs: ended) : distanceKm(gps, fromMs: accepted, toMs: started),
    started == null ? 0 : distanceKm(gps, fromMs: started, toMs: ended),
    started == null ? null : nearestFix(gps, started),
    started == null || t.endedAt == null ? null : nearestFix(gps, ended),
  );
}
