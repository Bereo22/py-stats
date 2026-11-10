import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/day_stats.dart';
import '../data/fuel_store.dart';
import '../data/periods.dart';
import '../format.dart';
import '../theme.dart';

class FuelPage extends StatefulWidget {
  final String logDir;
  const FuelPage({super.key, required this.logDir});

  @override
  State<FuelPage> createState() => _FuelPageState();
}

class _FuelPageState extends State<FuelPage> {
  late final FuelStore _store = FuelStore(widget.logDir);
  Period _period = Period.month;
  List<FuelEntry>? _entries;
  double _periodKm = 0;
  double _earnings = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _store.load();
    final keys = periodDays(_period);
    final stats = Totals((await loadDayStats(widget.logDir, keys)).values.toList());
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _periodKm = stats.km;
      _earnings = stats.earnings;
    });
  }

  Future<void> _add() async {
    final entry = await showModalBottomSheet<FuelEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBox,
      builder: (_) => const OnBox(child: _FuelForm()),
    );
    if (entry == null) return;
    final list = [...?_entries, entry]..sort((a, b) => b.date.compareTo(a.date));
    await _store.save(list);
    _load();
  }

  Future<void> _delete(FuelEntry e) async {
    final list = [...?_entries]..remove(e);
    await _store.save(list);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final start = parseDayKey(periodDays(_period).first);
    final inPeriod = entries?.where((e) => !e.date.isBefore(start)).toList() ?? [];
    final amount = inPeriod.fold<double>(0, (s, e) => s + e.amount);
    final liters = inPeriod.fold<double>(0, (s, e) => s + e.liters);

    return Scaffold(
      appBar: AppBar(title: const Text('Yakıt')),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: kGreen,
        foregroundColor: kDark,
        icon: const Icon(Icons.add),
        label: const Text('Yakıt ekle'),
      ),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                SegmentedButton<Period>(
                  segments: [for (final p in Period.values) ButtonSegment(value: p, label: Text(p.label))],
                  selected: {_period},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() => _period = s.first);
                    _load();
                  },
                ),
                const SizedBox(height: 16),
                Box(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Yakıt harcaması', style: TextStyle(color: kBoxMuted)),
                        const SizedBox(height: 4),
                        Text(money(amount),
                            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: kDark)),
                        const SizedBox(height: 16),
                        _row('Alınan yakıt', '${liters.toStringAsFixed(1)} L'),
                        _row('Ortalama litre fiyatı', liters > 0 ? money(amount / liters) : '-'),
                        _row('Bu dönemde gidilen yol', km(_periodKm)),
                        _row('Km başına yakıt maliyeti (yaklaşık)',
                            _periodKm > 0 && amount > 0 ? money(amount / _periodKm) : '-'),
                        _row('100 km\'de litre (yaklaşık)',
                            _periodKm > 0 && liters > 0 ? '${(liters / _periodKm * 100).toStringAsFixed(1)} L' : '-'),
                        const Divider(height: 24),
                        _row('Bu dönemdeki kazanç', money(_earnings)),
                        _row('Yakıtın kazanca oranı',
                            _earnings > 0 && amount > 0 ? '%${(amount / _earnings * 100).round()}' : '-'),
                        _row('Yakıt düşünce kalan', _earnings > 0 ? money(_earnings - amount) : '-'),
                        _row('Her 1 TL yakıta ciro',
                            _earnings > 0 && amount > 0 ? '${(_earnings / amount).toStringAsFixed(1)} TL' : '-'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Yaklaşık değerler, bu dönemde alınan yakıtın bu dönemde gidilen yola ve kazanca bölünmesiyle hesaplanır.',
                  style: TextStyle(color: kMuted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                const Text('Kayıtlar', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Henüz yakıt girilmedi.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                  ),
                for (final e in entries)
                  Dismissible(
                    key: ObjectKey(e),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: const Icon(Icons.delete_outline),
                    ),
                    onDismissed: (_) => _delete(e),
                    child: Box(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text('${money(e.amount)} · ${e.liters.toStringAsFixed(1)} L'),
                        subtitle: Text(
                          [
                            '${e.date.day}.${two(e.date.month)}.${e.date.year} ${hhmm(e.date)}',
                            '${money(e.pricePerLiter)}/L',
                            if (e.odometer != null) '${e.odometer} km',
                          ].join(' · '),
                          style: const TextStyle(color: kBoxMuted),
                        ),
                      ),
                    ),
                  ),
                if (entries.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Silmek için kaydı sola kaydır.', style: TextStyle(color: kMuted, fontSize: 12)),
                  ),
              ],
            ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: kBoxMuted))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

class _FuelForm extends StatefulWidget {
  const _FuelForm();

  @override
  State<_FuelForm> createState() => _FuelFormState();
}

class _FuelFormState extends State<_FuelForm> {
  final _liters = TextEditingController();
  final _amount = TextEditingController();
  final _odometer = TextEditingController();
  DateTime _date = DateTime.now();

  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.').trim());

  @override
  void dispose() {
    _liters.dispose();
    _amount.dispose();
    _odometer.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
  }

  void _save() {
    final liters = _num(_liters);
    final amount = _num(_amount);
    if (liters == null || amount == null || liters <= 0 || amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Litre ve tutarı gir.')));
      return;
    }
    Navigator.pop(
      context,
      FuelEntry(date: _date, liters: liters, amount: amount, odometer: _num(_odometer)?.round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Yakıt ekle', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimal,
            decoration: const InputDecoration(labelText: 'Tutar (TL)'),
          ),
          TextField(
            controller: _liters,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimal,
            decoration: const InputDecoration(labelText: 'Litre'),
          ),
          TextField(
            controller: _odometer,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Km sayacı (isteğe bağlı)'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text('${_date.day}.${two(_date.month)}.${_date.year}'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _save,
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Kaydet')),
          ),
        ],
      ),
    );
  }
}
