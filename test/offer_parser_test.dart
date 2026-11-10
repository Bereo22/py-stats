import 'package:flutter_test/flutter_test.dart';
import 'package:tag_stats/data/log_reader.dart';
import 'package:tag_stats/parsing/offer_parser.dart';

ScreenRecord rec(List<String> texts, {int second = 0}) => ScreenRecord(
      time: DateTime(2026, 10, 22, 21, 30, second),
      src: 'a11y',
      pkg: 'com.marti.tag',
      event: 'content',
      lat: 41.67,
      lng: 26.55,
      texts: texts,
      nodes: const [],
    );

// Texts as they appear on the offer card screenshot, one per view.
const offerTexts = [
  'G. Y.(4.56 ★)',
  '174 TL',
  'Ödeme Yöntemi',
  'Nakit',
  '11 dk (6.4 km) uzaklıkta',
  'ŞIŞLI, Nadide Sokak',
  '9 dk (2 km) uzaklıkta',
  'ŞIŞLI, Tolga Saraçoğlu/Showroom',
  'Kabul et',
  '6',
];

void main() {
  test('parses the offer card', () {
    final o = OfferParser.parse(rec(offerTexts))!;
    expect(o.customerInitials, 'G. Y.');
    expect(o.customerRating, 4.56);
    expect(o.price, 174);
    expect(o.payment, 'Nakit');
    expect(o.pickupMin, 11);
    expect(o.pickupKm, 6.4);
    expect(o.pickupAddress, 'ŞIŞLI, Nadide Sokak');
    expect(o.tripMin, 9);
    expect(o.tripKm, 2);
    expect(o.dropoffAddress, 'ŞIŞLI, Tolga Saraçoğlu/Showroom');
    expect(o.tlPerKm, closeTo(174 / 8.4, 0.001));
  });

  test('handles split nodes and joined lines', () {
    final o = OfferParser.parse(rec([
      'G. Y.',
      '(4.56',
      '1.250,50 TL',
      'Kart',
      '11 dk (850 m) uzaklıkta\nEdirne, Saraçlar Cd.',
      '9 dk (2,3 km) uzaklıkta Edirne, Selimiye',
      'Kabul et 5',
    ]))!;
    expect(o.customerInitials, 'G. Y.');
    expect(o.customerRating, 4.56);
    expect(o.price, 1250.5);
    expect(o.payment, 'Kart');
    expect(o.pickupKm, closeTo(0.85, 1e-9));
    expect(o.pickupAddress, 'Edirne, Saraçlar Cd.');
    expect(o.tripKm, 2.3);
    expect(o.dropoffAddress, 'Edirne, Selimiye');
  });

  test('ignores non-offer screens', () {
    expect(OfferParser.parse(rec(['Bronz', 'Ödüller', 'Davet Et', 'Meşgul', 'Müsait', 'TAG'])), isNull);
  });

  test('merges countdown snapshots of the same offer and groups customers', () {
    final countdown = [
      for (var s = 0; s < 6; s++)
        rec([...offerTexts.take(9), '${6 - s}'], second: s),
    ];
    final other = rec([
      'A. K.(4.90 ★)',
      '95 TL',
      'Nakit',
      '3 dk (1.1 km) uzaklıkta',
      'Edirne, Kaleiçi',
      '7 dk (3 km) uzaklıkta',
      'Edirne, Trakya Üniversitesi',
      'Kabul et',
    ], second: 40);
    final again = rec([...offerTexts], second: 50)
        .let((r) => ScreenRecord(
              time: r.time.add(const Duration(minutes: 5)),
              src: r.src,
              pkg: r.pkg,
              event: r.event,
              lat: r.lat,
              lng: r.lng,
              texts: r.texts,
              nodes: r.nodes,
            ));

    final offers = OfferParser.extract([...countdown, other, again]);
    expect(offers, hasLength(3));
    expect(offers.first.shownFor, const Duration(seconds: 5));

    final customers = OfferParser.customers(offers);
    expect(customers.first.key, 'G. Y. (4.56)');
    expect(customers.first.count, 2);
    expect(customers.first.totalPrice, 348);
  });

  test('turkish money parsing', () {
    expect(parseTurkishNumber('174'), 174);
    expect(parseTurkishNumber('174,50'), 174.5);
    expect(parseTurkishNumber('1.250'), 1250);
    expect(parseTurkishNumber('1.250,75'), 1250.75);
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
