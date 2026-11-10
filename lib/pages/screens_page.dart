import 'package:flutter/material.dart';

import '../data/log_reader.dart';
import '../format.dart';
import '../theme.dart';
import 'day_dropdown.dart';

/// Raw view of what the reader captured, to check that Martı's texts are visible.
class ScreensPage extends StatefulWidget {
  final String logDir;
  const ScreensPage({super.key, required this.logDir});

  @override
  State<ScreensPage> createState() => _ScreensPageState();
}

class _ScreensPageState extends State<ScreensPage> {
  late final LogReader _reader = LogReader(widget.logDir);
  List<String> _days = [];
  String? _day;
  List<ScreenRecord>? _records;
  int _gpsPoints = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final days = await _reader.days();
    setState(() => _days = days);
    await _load(days.isEmpty ? today() : days.first);
  }

  Future<void> _load(String day) async {
    setState(() {
      _day = day;
      _records = null;
    });
    final records = await _reader.screens(day);
    final gps = await _reader.gpsPointCount(day);
    if (mounted) {
      setState(() {
        _records = records.reversed.take(500).toList();
        _gpsPoints = gps;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ekran kayıtları'),
        actions: [DayDropdown(days: _days, value: _day, onChanged: _load)],
      ),
      body: records == null
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? const Center(child: Text('Kayıt yok.', style: TextStyle(color: kMuted)))
              : ListView.builder(
                  itemCount: records.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Text('Son ${records.length} ekran · $_gpsPoints GPS noktası',
                            style: const TextStyle(color: kMuted)),
                      );
                    }
                    return _RecordTile(records[i - 1]);
                  },
                ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final ScreenRecord r;
  const _RecordTile(this.r);

  @override
  Widget build(BuildContext context) {
    final toggles = r.nodes.where((n) => n.containsKey('chk') || n.containsKey('sd')).toList();
    return Box(
      child: ExpansionTile(
        shape: const Border(),
        title: Text(
          r.texts.isEmpty ? '(yazı yok - OCR gerekebilir)' : r.texts.join(' | '),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
        subtitle: Text('${hhmmss(r.time)} · ${r.src} · ${r.event} · ${r.nodes.length} öğe',
            style: const TextStyle(color: kBoxMuted, fontSize: 12)),
        children: [
          for (final n in r.nodes.take(150))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
              child: Text(
                [
                  '${'  ' * ((n['d'] as int?) ?? 0).clamp(0, 12)}${n['c'] ?? ''}',
                  if (n['t'] != null) '"${n['t']}"',
                  if (n['cd'] != null) 'açıklama="${n['cd']}"',
                  if (n['sd'] != null) 'durum="${n['sd']}"',
                  if (n['chk'] != null) 'işaretli=${n['chk']}',
                  if (n['id'] != null) '#${n['id']}',
                ].join(' '),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: kBoxMuted),
              ),
            ),
          if (toggles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${toggles.length} anahtar/durum öğesi bulundu',
                  style: const TextStyle(color: kDark, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
