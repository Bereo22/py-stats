String two(int n) => n.toString().padLeft(2, '0');

String hhmm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

String hhmmss(DateTime t) => '${hhmm(t)}:${two(t.second)}';

String money(double? v) => v == null ? '-' : '${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)} TL';

String km(double? v) => v == null ? '-' : '${v.toStringAsFixed(1)} km';

String today() {
  final n = DateTime.now();
  return '${n.year}-${two(n.month)}-${two(n.day)}';
}

/// "12 sn önce", "5 dk önce", or the clock time for older moments.
String ago(DateTime? t) {
  if (t == null) return 'hiç';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds} sn önce';
  if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
  return hhmm(t);
}
