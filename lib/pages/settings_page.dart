import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../format.dart';
import '../native/native_bridge.dart';
import '../theme.dart';
import 'screens_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  NativeStatus? _status;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await NativeBridge.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _toggleCapture(bool on) async {
    if (on) {
      await Permission.notification.request();
      final ok = await NativeBridge.startCapture();
      if (!ok) _snack('Ekran kaydı izni verilmedi.');
    } else {
      await NativeBridge.stopCapture();
    }
    await Future.delayed(const Duration(milliseconds: 400));
    _refresh();
  }

  Future<void> _export() async {
    final n = await NativeBridge.exportLogs();
    if (n == 0) _snack('Henüz kayıt yok.');
  }

  Future<void> _pickTarget() async {
    final s = _status;
    if (s == null) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kBox,
      builder: (ctx) => OnBox(
          child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Martı TAG hangisi?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            if (s.seenPkgs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Ekran okuyucuyu açıp Martı TAG\'i bir kez aç, burada listelenecek.'),
              ),
            for (final p in s.seenPkgs)
              ListTile(
                title: Text(p),
                trailing: p == s.targetPkg ? const Icon(Icons.check, color: kDark) : null,
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      )),
    );
    if (picked != null) {
      await NativeBridge.setTargetPackage(picked);
      _refresh();
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar ve kurulum')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const _Header('Veri toplama'),
                _StatusCard(
                  icon: Icons.accessibility_new,
                  title: 'Ekran okuyucu (erişilebilirlik)',
                  ok: s.a11yEnabled && s.a11yConnected,
                  subtitle: !s.a11yEnabled
                      ? 'Kapalı. Aşağıdaki kurulum adımlarını uygula.'
                      : s.a11yConnected
                          ? 'Çalışıyor'
                          : 'Açık ama bağlı değil; kapatıp tekrar aç',
                  action: TextButton(
                    onPressed: NativeBridge.openAccessibilitySettings,
                    child: const Text('Ayarlar'),
                  ),
                ),
                _StatusCard(
                  icon: Icons.local_taxi,
                  title: 'Martı TAG uygulaması',
                  ok: s.targetPkg != null,
                  subtitle: s.targetPkg ?? 'Henüz algılanmadı; Martı TAG\'i bir kez aç',
                  action: TextButton(onPressed: _pickTarget, child: const Text('Seç')),
                ),
                Box(
                  child: SwitchListTile(
                    secondary: IconBadge(Icons.document_scanner_outlined, active: s.ocrOnStart),
                    title: const Text('Başlatınca OCR\'yi de aç'),
                    subtitle: const Text(
                      'Ekran okuyucu Martı yazılarını göremezse aç. Her başlatmada ekran kaydı izni sorulur; "Tüm ekran"ı seç.',
                      style: TextStyle(color: kBoxMuted),
                    ),
                    value: s.ocrOnStart,
                    onChanged: (v) async {
                      await NativeBridge.setOcrOnStart(v);
                      _refresh();
                    },
                  ),
                ),
                Box(
                  child: SwitchListTile(
                    secondary: IconBadge(Icons.screenshot_monitor, active: s.capturing),
                    title: const Text('OCR şu an'),
                    subtitle: Text(
                      s.capturing ? 'Açık · son okuma ${ago(s.lastOcrAt)}' : 'Kapalı',
                      style: const TextStyle(color: kBoxMuted),
                    ),
                    value: s.capturing,
                    onChanged: _toggleCapture,
                  ),
                ),
                Box(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Durum', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _kv(
                          'Kayıt',
                          !s.tracking
                              ? 'Durdu'
                              : s.trackingStartedAt == null
                                  ? 'Çalışıyor'
                                  : 'Çalışıyor (başlangıç ${hhmm(s.trackingStartedAt!)})',
                        ),
                        _kv(
                          'Son konum',
                          s.locationAt == null
                              ? '-'
                              : '${ago(s.locationAt)} · ±${s.accuracy?.toStringAsFixed(0)} m',
                        ),
                        _kv('Kaydedilen Martı ekranı', '${s.screensWritten}'),
                        _kv('Son Martı olayı', ago(s.lastTargetEventAt)),
                        _kv('Öndeki uygulama', s.foregroundPkg ?? '-'),
                        _kv('Pil kısıtlaması', s.ignoringBatteryOptimizations ? 'Kapalı' : 'Açık (kapat)'),
                      ],
                    ),
                  ),
                ),
                Box(
                  child: ListTile(
                    leading: const IconBadge(Icons.list_alt),
                    title: const Text('Ham ekran kayıtları'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => ScreensPage(logDir: s.logDir))),
                  ),
                ),
                Box(
                  child: ListTile(
                    leading: const IconBadge(Icons.ios_share),
                    title: const Text('Kayıtları paylaş (zip)'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _export,
                  ),
                ),
                const _Header('Kurulum (Redmi)'),
                _Step(
                  n: 1,
                  title: 'Konum ve bildirim izni',
                  body: 'Konum için "Uygulamayı kullanırken" yeterli. Bildirim izni, arka planda çalıştığını gösteren bildirim için gerekli.',
                  button: 'İzin ver',
                  onPressed: () async {
                    await Permission.locationWhenInUse.request();
                    await Permission.notification.request();
                  },
                ),
                const _Step(
                  n: 2,
                  title: 'Kısıtlı ayarlara izin ver',
                  body: 'APK ile kurulan uygulamalarda erişilebilirlik anahtarı gri gelir. '
                      'Uygulama bilgisi ekranında sağ üstteki ⋮ menüsünden "Kısıtlı ayarlara izin ver"i seç. '
                      'Menüde görünmüyorsa önce 3. adımı dene; açılmayınca bu seçenek belirir.',
                  button: 'Uygulama bilgisi',
                  onPressed: NativeBridge.openAppDetails,
                ),
                const _Step(
                  n: 3,
                  title: 'Ekran okuyucuyu aç',
                  body: 'Ayarlar > Erişilebilirlik > İndirilen uygulamalar > "PY Stats - Martı ekran okuyucu" > Aç.',
                  button: 'Erişilebilirlik',
                  onPressed: NativeBridge.openAccessibilitySettings,
                ),
                const _Step(
                  n: 4,
                  title: 'Otomatik başlatma',
                  body: 'Güvenlik uygulamasındaki otomatik başlatma listesinde PY Stats\'ı aç. '
                      'Kapalı kalırsa telefon servisi sessizce durdurabilir.',
                  button: 'Otomatik başlatma',
                  onPressed: NativeBridge.openAutostartSettings,
                ),
                const _Step(
                  n: 5,
                  title: 'Pil kısıtlamasını kaldır',
                  body: 'Çıkan pencerede izin ver. Ardından Uygulama bilgisi > Pil tasarrufu > "Kısıtlama yok" seç.',
                  button: 'Pil ayarı',
                  onPressed: NativeBridge.requestIgnoreBatteryOptimizations,
                ),
                const _Step(
                  n: 6,
                  title: 'Son uygulamalarda kilitle',
                  body: 'Son uygulamalar ekranını aç, PY Stats kartına basılı tut ve kilit simgesine dokun. '
                      'Böylece "tümünü temizle" uygulamayı kapatmaz.',
                ),
              ],
            ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(color: kBoxMuted))),
            Flexible(child: Text(v, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
        child: Text(text, style: const TextStyle(color: kGreen, fontWeight: FontWeight.w600)),
      );
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool ok;
  final Widget action;

  const _StatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ok,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Box(
      child: ListTile(
        leading: IconBadge(icon, active: ok),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(color: kBoxMuted)),
        trailing: action,
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String title;
  final String body;
  final String? button;
  final VoidCallback? onPressed;

  const _Step({required this.n, required this.title, required this.body, this.button, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Box(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: kGreen,
              child: Text('$n', style: const TextStyle(color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(body, style: const TextStyle(color: kBoxMuted)),
                  if (button != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: onPressed, child: Text(button!)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
