import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tag_stats/data/day_stats.dart';
import 'package:tag_stats/data/log_reader.dart';
import 'package:tag_stats/parsing/marti_text.dart';
import 'package:tag_stats/parsing/trip_parser.dart';

/// OCR records of one real ride, anonymized: customer initials replaced, GPS shifted.
List<ScreenRecord> fixture() => parseScreensFile('test/fixtures/marti_trip.jsonl');

DateTime at(int h, int m, int s) => DateTime(2026, 10, 23, h, m, s);

void main() {
  test('classifies Martı screens', () {
    expect(MartiText.classify(['Meşgul', 'Müsait', 'Yolcu aranıyor']), ScreenKind.available);
    expect(MartiText.classify(['Meşgul', 'Müsait', 'Bronz']), ScreenKind.busy);
    expect(MartiText.classify(['130 TL', 'Kabul et', 'Düşük iptal']), ScreenKind.offer);
    expect(MartiText.classify(['A. B.(4.86 t)', 'X İptal Et', 'Adresteyim']), ScreenKind.toPickup);
    expect(MartiText.classify(['Yolculuk Doğrulaması', 'Yolcunun paylaştığı kodu gir']), ScreenKind.code);
    expect(MartiText.classify(['130 TL', 'O Nakit', 'Bitir', 'Yol Tarifi']), ScreenKind.onTrip);
    expect(MartiText.classify(['Yolculuğunu Değerlendir', 'Harika!']), ScreenKind.rating);
    expect(MartiText.classify(['Instagram', 'Reels']), ScreenKind.other);
  });

  test('reads OCR variants', () {
    expect(MartiText.parseCustomer('A. B.(4.86 +)'), ('A. B.', 4.86));
    expect(MartiText.parseCustomer('A.B.(4.86 *)'), ('A. B.', 4.86));
    expect(MartiText.parseRatingOnly('V 4.86'), 4.86);
    expect(MartiText.parsePayment('(O Nakit'), 'Nakit');
    expect(MartiText.parsePayment('Ödeme Yöntemi'), isNull);
    expect(MartiText.parsePrice('130 TL'), 130);
    expect(MartiText.parsePrice('D535'), isNull);
  });

  test('real ride: offer, pickup, code, ride, rating', () {
    final log = TripParser.parse(fixture());

    final offer = log.offers.single;
    expect(offer.price, 130);
    expect(offer.customerRating, 4.86);
    expect(offer.pickupMin, 3);
    expect(offer.pickupKm, 1.8);
    expect(offer.tripMin, 6);
    expect(offer.tripKm, 3);
    expect(offer.dropoffAddress, contains('Ayşekadın'));
    expect(offer.accepted, isTrue);

    final trip = log.trips.single;
    expect(trip.completed, isTrue);
    expect(trip.price, 130);
    expect(trip.payment, 'Nakit');
    expect(trip.customerInitials, 'A. B.');
    expect(trip.customerRating, 4.86);
    expect(trip.dropoffAddress, contains('Ayşekadın'));
    expect(trip.acceptedAt.difference(at(21, 41, 40)).inSeconds.abs(), lessThan(10));
    expect(trip.arrivedAt!.difference(at(21, 45, 16)).inSeconds.abs(), lessThan(30));
    expect(trip.startedAt!.difference(at(21, 45, 32)).inSeconds.abs(), lessThan(30));
    expect(trip.endedAt!.difference(at(21, 56, 31)).inSeconds.abs(), lessThan(10));
  });

  test('real evening: three rides, one canceled by driver, one by customer', () {
    final log = TripParser.parse(parseScreensFile('test/fixtures/marti_evening.jsonl'));
    final done = log.trips.where((t) => t.completed).toList();
    expect(done.map((t) => t.price), [191, 235, 164]);
    expect(done.map((t) => t.customerInitials), ['M. T.', 'E. F.', 'M. T.']);
    expect(done.map((t) => t.startedAt!.hour * 60 + t.startedAt!.minute), [21 * 60 + 15, 22 * 60 + 30, 23 * 60 + 19]);

    final canceled = log.trips.where((t) => t.canceled).toList();
    expect(canceled.map((t) => t.price), [135, 140]);
    expect(canceled.map((t) => t.canceledBy), [CancelBy.driver, CancelBy.customer]);

    expect(log.offers.map((o) => o.price), [191, 135, 202, 140, 235, 164]);
    expect(log.offers.where((o) => o.accepted).length, 5);
    expect(log.offers.where((o) => o.canceled).map((o) => o.price), [135, 140]);
    expect(log.offers.map((o) => o.customerRating), everyElement(isNotNull));
    expect(log.offers.last.dropoffAddress, 'EDIRNE MERKEZ, Palmiye Suites Otel');
    expect(TripParser.customers(log.trips).first.key, 'M. T. (4.76)');
  });

  test('real ride: gps splits pickup and ride km', () {
    final dir = Directory.systemTemp.createTempSync('tag_stats_trip');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('test/fixtures/marti_trip.jsonl').copySync('${dir.path}/screens_2026-10-23.jsonl');
    File('test/fixtures/marti_trip_gps.jsonl').copySync('${dir.path}/gps_2026-10-23.jsonl');

    final day = computeDayStats(dir.path, ['2026-10-23'])['2026-10-23']!;
    final t = day.trips.single;
    final totals = Totals([day]);
    expect(t.pickupKm, closeTo(1.8, 0.8));
    expect(t.rideKm, closeTo(3.0, 1.0));
    expect(totals.earnings, 130);
    expect(totals.emptyKm, greaterThan(0));
    expect(t.pickupPoint, isNotNull);
    expect(t.dropoffPoint, isNotNull);
  });
}
