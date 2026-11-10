/// Text helpers for Martı TAG screens as read by OCR or accessibility.
library;

/// Lowercase ASCII-folded form, so OCR variants like "aranıyor"/"araniyor" compare equal.
String fold(String s) {
  const from = 'İIıŞşĞğÜüÖöÇçÂâÎîÛû';
  const to = 'iiissgguuooccaaiiuu';
  final b = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    if (ch == 0x0307) continue;
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c.toLowerCase());
  }
  return b.toString();
}

enum ScreenKind {
  /// Home screen, status "Müsait" (looking for rides).
  available,

  /// Home screen without a searching status, e.g. switched to "Meşgul".
  busy,
  offer,

  /// Ride accepted, driving to the customer.
  toPickup,

  /// Entering the customer's code at the pickup.
  code,

  /// Customer on board ("Bitir" visible).
  onTrip,

  /// "Yolculuğunu Değerlendir" after the ride.
  rating,
  other,
}

class MartiText {
  static const _searching = ['cevrimicisin', 'araniyor', 'hazirsin'];

  static ScreenKind classify(List<String> lines) {
    final f = lines.map(fold).toList();
    final all = f.join('\n');
    bool line(bool Function(String) test) => f.any(test);

    if (all.contains('yolculugunu degerlendir')) return ScreenKind.rating;
    if (line((l) => RegExp(r'^\W{0,3}kabul\s*et[\W\d]{0,4}$').hasMatch(l))) return ScreenKind.offer;
    if (all.contains('yolculuk dogrulamasi') || all.contains('yolculugu baslat') || all.contains('kodu gir')) {
      return ScreenKind.code;
    }
    if (line((l) => RegExp(r'^\W{0,3}(yolculugu\s*)?bitir\W{0,3}$').hasMatch(l))) return ScreenKind.onTrip;
    if (line((l) => l.contains('iptal et') && l.length < 16) ||
        all.contains('adresteyim') ||
        all.contains('adrese geldim') ||
        all.contains('yolcuyu ara') ||
        (all.contains('yolculuk tercihleri') && line((l) => customer.hasMatch(l)))) {
      return ScreenKind.toPickup;
    }
    final home = line((l) => l == 'musait') && line((l) => l == 'mesgul');
    if (home) {
      return _searching.any(all.contains) ? ScreenKind.available : ScreenKind.busy;
    }
    if (all.contains('selfie dogrulamasi')) return ScreenKind.busy;
    return ScreenKind.other;
  }

  /// "N. K.(4.86 t)" -> initials, rating. OCR often garbles what follows the rating.
  static final customer = RegExp(r'^((?:[A-ZÇĞİÖŞÜ]\.\s*){1,4})\s*\(\s*(\d[.,]\d{1,2})');

  /// "V 4.86" / "4.6 *" / "4.85 t": rating shown on the offer card without initials.
  static final ratingOnly = RegExp(r'^[^\d\s]{0,2}\s*\(?\s*(\d[.,]\d{1,2})\s*[^\d\s]{0,2}\s*\)?$');
  static final _unit = RegExp(r'\b(km|dk|m|tl)\b', caseSensitive: false);

  static final leg = RegExp(r'(\d+)\s*dk\s*\(\s*([\d.,]+)\s*(km|m)\s*\)', caseSensitive: false);

  static final _price = RegExp(r'(?:^|[^\d.,])(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d+(?:,\d{1,2})?)\s*(?:TL|₺)(?![A-Za-z])',
      caseSensitive: false);
  static final _pricePrefixed = RegExp(r'₺\s*(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d+(?:,\d{1,2})?)');

  static (String, double)? parseCustomer(String line) {
    final m = customer.firstMatch(line);
    if (m == null) return null;
    final rating = parseDecimal(m.group(2)!);
    if (rating == null || rating < 1 || rating > 5) return null;
    return (normalizeInitials(m.group(1)!), rating);
  }

  static double? parseRatingOnly(String line) {
    if (_unit.hasMatch(line)) return null;
    final m = ratingOnly.firstMatch(line);
    if (m == null) return null;
    final r = parseDecimal(m.group(1)!);
    return r != null && r >= 1 && r <= 5 ? r : null;
  }

  /// "N.K." / "N. K." -> "N. K."
  static String normalizeInitials(String s) =>
      RegExp(r'[A-ZÇĞİÖŞÜ]').allMatches(s).map((m) => '${m.group(0)}.').join(' ');

  static double? parsePrice(String line) {
    final m = _price.firstMatch(line) ?? _pricePrefixed.firstMatch(line);
    if (m == null) return null;
    final v = parseTurkishNumber(m.group(1)!);
    return v != null && v > 0 && v < 100000 ? v : null;
  }

  /// "(O Nakit" / "Nakit" -> "Nakit". The "Ödeme Yöntemi" header is not a payment.
  static String? parsePayment(String line) {
    final f = fold(line);
    if (f.contains('odeme')) return null;
    if (RegExp(r'\bnakit\b').hasMatch(f)) return 'Nakit';
    if (RegExp(r'\b(kredi |banka )?kart\b').hasMatch(f)) return 'Kart';
    if (f.contains('cuzdan')) return 'Cüzdan';
    return null;
  }

  /// "3 dk (1.8 km) uzaklıkta" -> (3, 1.8, rest of the line after the leg).
  static (int?, double?, String)? parseLeg(String line) {
    final m = leg.firstMatch(line);
    if (m == null) return null;
    var km = parseDecimal(m.group(2)!);
    if (km != null && m.group(3)!.toLowerCase() == 'm') km = km / 1000;
    final rest = line.substring(m.end).replaceFirst(RegExp(r'^\s*uzakl\S*', caseSensitive: false), '').trim();
    return (int.tryParse(m.group(1)!), km, cleanAddress(rest));
  }

  /// Drops the pin icon OCR reads as a leading "O " / "0 " / "©".
  static String cleanAddress(String s) =>
      s.replaceFirst(RegExp(r'^(?:[Oo0]\s+|[©@®•]\s*)(?=[A-ZÇĞİÖŞÜ]{3})'), '').trim();

  /// Cancel flow markers, folded.
  static bool driverCancelDialog(String folded) => folded.contains('eslesmeyi neden iptal');
  static bool requestGone(String folded) =>
      folded.contains('talep artik gecerli degil') || folded.contains('yolcu iptal etti');

  /// Address lines read like "EDIRNE MERKEZ, Ayşekadın Yerleşkesi".
  static bool isAddress(String s) =>
      s.length >= 6 &&
      s.contains(RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]{3}')) &&
      !leg.hasMatch(s) &&
      parsePrice(s) == null &&
      !fold(s).contains('kabul et');
}

/// "6.4" / "6,4" -> 6.4
double? parseDecimal(String s) => double.tryParse(s.replaceAll(',', '.'));

/// Turkish money: "1.250" -> 1250, "174,50" -> 174.5, "174" -> 174.
double? parseTurkishNumber(String s) {
  var v = s.replaceAll(' ', '');
  if (v.contains(',')) {
    v = v.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(v)) {
    v = v.replaceAll('.', '');
  }
  return double.tryParse(v);
}
