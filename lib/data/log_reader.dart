import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

class ScreenRecord {
  final DateTime time;
  final String src;
  final String? pkg;
  final String event;
  final double? lat;
  final double? lng;
  final List<String> texts;
  final List<Map<String, dynamic>> nodes;

  ScreenRecord({
    required this.time,
    required this.src,
    required this.pkg,
    required this.event,
    required this.lat,
    required this.lng,
    required this.texts,
    required this.nodes,
  });

  factory ScreenRecord.fromJson(Map<String, dynamic> j) {
    final loc = j['loc'] as Map<String, dynamic>?;
    return ScreenRecord(
      time: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
      src: j['src'] as String? ?? '',
      pkg: j['pkg'] as String?,
      event: j['ev'] as String? ?? '',
      lat: (loc?['lat'] as num?)?.toDouble(),
      lng: (loc?['lng'] as num?)?.toDouble(),
      texts: ((j['texts'] as List?) ?? const []).cast<String>(),
      nodes: ((j['nodes'] as List?) ?? const []).cast<Map<String, dynamic>>(),
    );
  }

  /// Text lines in reading order. OCR returns blocks in arbitrary order, so they are
  /// sorted by row (top) and then left to right; accessibility text is already in order.
  List<String> get lines {
    final boxed = src == 'ocr'
        ? nodes.where((n) => n['t'] is String && n['b'] is List && (n['b'] as List).length == 4).toList()
        : const <Map<String, dynamic>>[];
    final ordered = boxed.length == texts.length ? _readingOrder(boxed) : texts;
    return ordered
        .expand((t) => t.split('\n'))
        .map((t) => t.replaceAll('\u00A0', ' ').trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  static List<String> _readingOrder(List<Map<String, dynamic>> nodes) {
    num top(Map<String, dynamic> n) => (n['b'] as List)[1] as num;
    num left(Map<String, dynamic> n) => (n['b'] as List)[0] as num;
    final byTop = [...nodes]..sort((a, b) => top(a).compareTo(top(b)));
    final out = <String>[];
    var row = <Map<String, dynamic>>[];
    void flush() {
      row.sort((a, b) => left(a).compareTo(left(b)));
      out.addAll(row.map((n) => n['t'] as String));
      row = [];
    }

    for (final n in byTop) {
      if (row.isNotEmpty && top(n) - top(row.first) > 16) flush();
      row.add(n);
    }
    flush();
    return out;
  }
}

class LogReader {
  final String dir;
  LogReader(this.dir);

  static final _screensFile = RegExp(r'^screens_(\d{4}-\d{2}-\d{2})\.jsonl$');

  /// Days that have a screens log, newest first (yyyy-MM-dd).
  Future<List<String>> days() async {
    final d = Directory(dir);
    if (!await d.exists()) return [];
    final days = <String>[];
    await for (final e in d.list()) {
      final m = _screensFile.firstMatch(e.uri.pathSegments.last);
      if (m != null) days.add(m.group(1)!);
    }
    days.sort((a, b) => b.compareTo(a));
    return days;
  }

  Future<List<ScreenRecord>> screens(String day) {
    final path = '$dir${Platform.pathSeparator}screens_$day.jsonl';
    return Isolate.run(() => parseScreensFile(path));
  }

  Future<int> gpsPointCount(String day) async {
    final f = File('$dir${Platform.pathSeparator}gps_$day.jsonl');
    if (!await f.exists()) return 0;
    var n = 0;
    await for (final _ in f.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      n++;
    }
    return n;
  }
}

List<ScreenRecord> parseScreensFile(String path) {
  final f = File(path);
  if (!f.existsSync()) return [];
  final out = <ScreenRecord>[];
  for (final line in f.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    try {
      out.add(ScreenRecord.fromJson(jsonDecode(line) as Map<String, dynamic>));
    } catch (_) {
      // A line can be cut short if the app was killed mid-write.
    }
  }
  return out;
}
