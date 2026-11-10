import 'dart:convert';
import 'dart:io';

class FuelEntry {
  final DateTime date;
  final double liters;
  final double amount;
  final int? odometer;

  FuelEntry({required this.date, required this.liters, required this.amount, this.odometer});

  double get pricePerLiter => liters > 0 ? amount / liters : 0;

  Map<String, dynamic> toJson() => {
        't': date.millisecondsSinceEpoch,
        'l': liters,
        'tl': amount,
        if (odometer != null) 'km': odometer,
      };

  factory FuelEntry.fromJson(Map<String, dynamic> j) => FuelEntry(
        date: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
        liters: (j['l'] as num).toDouble(),
        amount: (j['tl'] as num).toDouble(),
        odometer: (j['km'] as num?)?.toInt(),
      );
}

/// Fuel entries kept next to the logs so they are included in the exported zip.
class FuelStore {
  final File _file;
  FuelStore(String logDir) : _file = File('$logDir${Platform.pathSeparator}fuel.json');

  Future<List<FuelEntry>> load() async {
    if (!await _file.exists()) return [];
    final list = jsonDecode(await _file.readAsString()) as List;
    return list.map((e) => FuelEntry.fromJson(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> save(List<FuelEntry> entries) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()));
  }
}
