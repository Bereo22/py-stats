import '../data/log_reader.dart';
import 'marti_text.dart';
import 'offer_parser.dart';

enum CancelBy { driver, customer, unknown }

extension CancelByLabel on CancelBy {
  String get label => switch (this) {
        CancelBy.driver => 'Sen iptal ettin',
        CancelBy.customer => 'Yolcu iptal etti',
        CancelBy.unknown => 'İptal edildi',
      };
}

class Trip {
  /// Ride accepted (offer card left the screen), or the first ride screen seen.
  DateTime acceptedAt;

  /// Reached the pickup: code entry or the first on-trip screen.
  DateTime? arrivedAt;

  /// Customer on board.
  DateTime? startedAt;

  /// Rating screen after "Bitir", or the home screen when the rating was not seen.
  DateTime? endedAt;
  DateTime lastSeen;
  bool canceled = false;
  CancelBy? canceledBy;
  bool _driverCancelDialog = false;

  String? customerInitials;
  double? customerRating;
  String? payment;
  String? pickupAddress;
  String? dropoffAddress;

  /// Martı's estimates from the offer card.
  int? estPickupMin;
  double? estPickupKm;
  int? estTripMin;
  double? estTripKm;
  Offer? offer;

  final Map<double, int> _priceVotes = {};

  Trip(this.acceptedAt) : lastSeen = acceptedAt;

  /// Most frequently read fare; single OCR misreads ("30 TL" for "130 TL") get outvoted.
  double? get price {
    if (_priceVotes.isEmpty) return null;
    return _priceVotes.entries.reduce((a, b) => b.value > a.value || (b.value == a.value && b.key > a.key) ? b : a).key;
  }

  bool get completed => !canceled && startedAt != null && endedAt != null;

  /// Counts toward earnings: started and not canceled (may still be in progress).
  bool get paid => !canceled && startedAt != null;

  String get customerKey => '${customerInitials ?? '?'} (${customerRating?.toStringAsFixed(2) ?? '?'})';

  void _vote(double? p, [int weight = 1]) {
    if (p != null) _priceVotes[p] = (_priceVotes[p] ?? 0) + weight;
  }

  void _linkOffer(Offer o) {
    offer = o;
    o.accepted = true;
    customerInitials ??= o.customerInitials;
    customerRating ??= o.customerRating;
    payment ??= o.payment;
    pickupAddress ??= o.pickupAddress;
    dropoffAddress ??= o.dropoffAddress;
    estPickupMin = o.pickupMin;
    estPickupKm = o.pickupKm;
    estTripMin = o.tripMin;
    estTripKm = o.tripKm;
    _vote(o.price, 2);
  }

  void _absorb(List<String> lines, ScreenKind kind) {
    final legs = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final c = MartiText.parseCustomer(line);
      if (c != null) {
        customerInitials ??= c.$1;
        customerRating ??= c.$2;
        continue;
      }
      final leg = MartiText.parseLeg(line);
      if (leg != null) {
        var address = leg.$3;
        if (address.isEmpty && i + 1 < lines.length && MartiText.isAddress(lines[i + 1])) {
          address = MartiText.cleanAddress(lines[++i]);
        }
        legs.add(address);
        continue;
      }
      final p = MartiText.parsePrice(line);
      if (p != null) {
        _vote(p);
        continue;
      }
      payment ??= MartiText.parsePayment(line);
    }
    String? nonEmpty(String s) => s.isEmpty ? null : s;
    if (kind == ScreenKind.toPickup && legs.length >= 2) {
      pickupAddress ??= nonEmpty(legs[0]);
      dropoffAddress ??= nonEmpty(legs[1]);
    } else if (kind == ScreenKind.onTrip && legs.isNotEmpty) {
      dropoffAddress ??= nonEmpty(legs.last);
    }
  }
}

class TripLog {
  final List<Trip> trips;
  final List<Offer> offers;
  TripLog(this.trips, this.offers);
}

class CustomerStats {
  final String key;
  final List<Trip> trips;
  CustomerStats(this.key, this.trips);

  int get count => trips.length;
  double get total => trips.fold(0, (s, t) => s + (t.price ?? 0));
  DateTime get last => trips.map((t) => t.acceptedAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

class TripParser {
  /// An offer accepted this long before the first ride screen is linked to that ride.
  static const offerLink = Duration(minutes: 2);

  /// The rating screen can be missed; a home screen this soon after the ride closes it at that time.
  static const homeCloses = Duration(minutes: 5);

  /// Anything quieter than this is not the same ride any more.
  static const staleAfter = Duration(hours: 2);

  static TripLog parse(List<ScreenRecord> records) {
    final sorted = [...records]..sort((a, b) => a.time.compareTo(b.time));
    final offers = OfferParser.extract(sorted);
    final trips = <Trip>[];
    Trip? cur;

    void close({DateTime? end, bool requestGone = false}) {
      final t = cur!;
      if (t.startedAt == null) {
        t
          ..canceled = true
          ..canceledBy = t._driverCancelDialog
              ? CancelBy.driver
              : requestGone
                  ? CancelBy.customer
                  : CancelBy.unknown;
        t.offer?.canceled = true;
      } else {
        t.endedAt ??= end ?? t.lastSeen;
      }
      trips.add(t);
      cur = null;
    }

    Trip open(DateTime at) {
      final t = Trip(at);
      final candidates = offers.where((o) =>
          !o.accepted && !o.lastSeen.isAfter(at) && at.difference(o.lastSeen) <= offerLink);
      if (candidates.isNotEmpty) {
        final o = candidates.last;
        t
          ..acceptedAt = o.lastSeen
          .._linkOffer(o);
      }
      return t;
    }

    for (final r in sorted) {
      final lines = r.lines;
      final kind = MartiText.classify(lines);
      final folded = fold(lines.join('\n'));
      if (cur != null && cur!.startedAt == null && MartiText.driverCancelDialog(folded)) {
        cur!._driverCancelDialog = true;
      }
      if (cur != null && cur!.startedAt == null && MartiText.requestGone(folded)) {
        close(requestGone: true);
        continue;
      }
      if (kind == ScreenKind.other || kind == ScreenKind.offer) continue;

      if (cur != null && r.time.difference(cur!.lastSeen) > staleAfter) close();

      switch (kind) {
        case ScreenKind.toPickup:
          if (cur != null && cur!.startedAt != null) close();
          cur ??= open(r.time);
        case ScreenKind.code:
          cur ??= open(r.time);
          cur!.arrivedAt ??= r.time;
        case ScreenKind.onTrip:
          cur ??= open(r.time);
          cur!
            ..arrivedAt ??= r.time
            ..startedAt ??= r.time;
        case ScreenKind.rating:
          if (cur == null) continue;
          cur!
            ..startedAt ??= cur!.arrivedAt ?? cur!.acceptedAt
            ..endedAt = r.time;
          close();
          continue;
        case ScreenKind.available:
        case ScreenKind.busy:
          if (cur != null) {
            final soon = r.time.difference(cur!.lastSeen) <= homeCloses;
            close(end: soon ? r.time : null);
          }
          continue;
        case ScreenKind.offer:
        case ScreenKind.other:
          continue;
      }
      cur!
        ..lastSeen = r.time
        .._absorb(lines, kind);
    }
    if (cur != null) trips.add(cur!);
    return TripLog(trips, offers);
  }

  static List<CustomerStats> customers(Iterable<Trip> trips) {
    final map = <String, List<Trip>>{};
    for (final t in trips) {
      if (!t.paid || t.customerInitials == null) continue;
      map.putIfAbsent(t.customerKey, () => []).add(t);
    }
    return map.entries.map((e) => CustomerStats(e.key, e.value)).toList()
      ..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : b.total.compareTo(a.total));
  }
}
