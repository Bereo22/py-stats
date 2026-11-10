import 'dart:io';
import 'dart:isolate';

import '../data/log_reader.dart';
import 'marti_text.dart';

export 'marti_text.dart' show parseDecimal, parseTurkishNumber;

/// Offers for the given day keys, parsed off the UI thread.
Future<List<Offer>> loadOffers(String dir, List<String> days) => Isolate.run(() {
      final out = <Offer>[];
      for (final day in days) {
        out.addAll(OfferParser.extract(
            parseScreensFile('$dir${Platform.pathSeparator}screens_$day.jsonl')));
      }
      return out;
    });

class Offer {
  DateTime firstSeen;
  DateTime lastSeen;
  String? customerInitials;
  double? customerRating;
  double? price;
  String? payment;
  int? pickupMin;
  double? pickupKm;
  String? pickupAddress;
  int? tripMin;
  double? tripKm;
  String? dropoffAddress;
  double? lat;
  double? lng;
  String src;

  /// Set when a trip was started from this offer.
  bool accepted = false;

  /// The trip from this offer was canceled before the customer got in.
  bool canceled = false;

  Offer({required this.firstSeen, required this.src}) : lastSeen = firstSeen;

  /// Initials + rating; not unique, but the closest thing to a customer id Martı shows.
  String get customerKey {
    final r = customerRating?.toStringAsFixed(2);
    if (customerInitials == null) return r == null ? '?' : '★ $r';
    return '$customerInitials (${r ?? '?'})';
  }

  double? get totalKm =>
      pickupKm == null && tripKm == null ? null : (pickupKm ?? 0) + (tripKm ?? 0);

  double? get tlPerKm {
    final km = totalKm;
    if (price == null || km == null || km <= 0) return null;
    return price! / km;
  }

  Duration get shownFor => lastSeen.difference(firstSeen);

  String get _identity =>
      '${price ?? ''}|${pickupAddress ?? ''}|${dropoffAddress ?? ''}|${customerInitials ?? ''}';

  void absorb(Offer o) {
    lastSeen = o.lastSeen.isAfter(lastSeen) ? o.lastSeen : lastSeen;
    customerInitials ??= o.customerInitials;
    customerRating ??= o.customerRating;
    price ??= o.price;
    payment ??= o.payment;
    pickupMin ??= o.pickupMin;
    pickupKm ??= o.pickupKm;
    pickupAddress ??= o.pickupAddress;
    tripMin ??= o.tripMin;
    tripKm ??= o.tripKm;
    dropoffAddress ??= o.dropoffAddress;
    lat ??= o.lat;
    lng ??= o.lng;
  }
}

class CustomerSummary {
  final String key;
  final List<Offer> offers;
  CustomerSummary(this.key, this.offers);

  int get count => offers.length;
  double get totalPrice => offers.fold(0, (s, o) => s + (o.price ?? 0));
  DateTime get lastSeen =>
      offers.map((o) => o.lastSeen).reduce((a, b) => a.isAfter(b) ? a : b);
}

class OfferParser {
  static final _initialsOnly = RegExp(r'^(?:[A-ZÇĞİÖŞÜ]\.\s*){1,4}$');

  /// Parses one screen; null if it is not a ride offer.
  static Offer? parse(ScreenRecord r) {
    final lines = r.lines;
    if (MartiText.classify(lines) != ScreenKind.offer) return null;

    final o = Offer(firstSeen: r.time, src: r.src)
      ..lat = r.lat
      ..lng = r.lng;

    var legIndex = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final next = i + 1 < lines.length ? lines[i + 1] : null;

      final leg = MartiText.parseLeg(line);
      if (leg != null) {
        var (min, km, address) = leg;
        if (address.isEmpty && next != null && MartiText.isAddress(next)) {
          address = MartiText.cleanAddress(next);
          i++;
        }
        if (legIndex == 0) {
          o
            ..pickupMin = min
            ..pickupKm = km
            ..pickupAddress = address.isEmpty ? null : address;
        } else if (legIndex == 1) {
          o
            ..tripMin = min
            ..tripKm = km
            ..dropoffAddress = address.isEmpty ? null : address;
        }
        legIndex++;
        continue;
      }

      if (o.customerInitials == null) {
        final c = MartiText.parseCustomer(line);
        if (c != null) {
          o
            ..customerInitials = c.$1
            ..customerRating = c.$2;
          continue;
        }
        if (_initialsOnly.hasMatch(line)) {
          o.customerInitials = MartiText.normalizeInitials(line);
          final rating = next == null ? null : MartiText.parseRatingOnly(next);
          if (rating != null) {
            o.customerRating = rating;
            i++;
          }
          continue;
        }
      }

      if (o.price == null) {
        final p = MartiText.parsePrice(line);
        if (p != null) {
          o.price = p;
          continue;
        }
      }

      if (o.customerRating == null && legIndex == 0) {
        final rating = MartiText.parseRatingOnly(line);
        if (rating != null) {
          o.customerRating = rating;
          continue;
        }
      }

      o.payment ??= MartiText.parsePayment(line);
    }
    return o;
  }

  /// Parses offers from a day's records and merges the repeated snapshots of the same card.
  static List<Offer> extract(List<ScreenRecord> records) {
    final sorted = [...records]..sort((a, b) => a.time.compareTo(b.time));
    final offers = <Offer>[];
    for (final r in sorted) {
      final o = parse(r);
      if (o == null) continue;
      final prev = offers.isEmpty ? null : offers.last;
      final gap = prev == null ? null : o.firstSeen.difference(prev.lastSeen);
      if (prev != null &&
          gap! < const Duration(seconds: 60) &&
          (_compatible(prev, o) || (gap <= const Duration(seconds: 15) && prev.price != null && prev.price == o.price))) {
        prev.absorb(o);
      } else {
        offers.add(o);
      }
    }
    return offers;
  }

  /// Snapshots of one card a few seconds apart. OCR reads the addresses slightly differently
  /// each time, so only the fare, leg lengths and customer are compared.
  static bool _compatible(Offer a, Offer b) {
    bool same<T>(T? x, T? y) => x == null || y == null || x == y;
    return same(a.price, b.price) &&
        same(a.pickupKm, b.pickupKm) &&
        same(a.tripKm, b.tripKm) &&
        same(a.customerInitials, b.customerInitials) &&
        a._identity.isNotEmpty;
  }

  static List<CustomerSummary> customers(List<Offer> offers) {
    final map = <String, List<Offer>>{};
    for (final o in offers) {
      if (o.customerInitials == null) continue;
      map.putIfAbsent(o.customerKey, () => []).add(o);
    }
    final list = map.entries.map((e) => CustomerSummary(e.key, e.value)).toList()
      ..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : b.totalPrice.compareTo(a.totalPrice));
    return list;
  }
}
