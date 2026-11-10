import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/day_stats.dart';
import '../data/fuel_store.dart';
import '../data/periods.dart';
import '../format.dart';
import '../native/native_bridge.dart';
import '../theme.dart';
import 'activity_page.dart';
import 'density_page.dart';
import 'earnings_page.dart';
import 'fuel_page.dart';
import 'heatmap_page.dart';
import 'offers_page.dart';
import 'region_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  NativeStatus? _status;
  Totals? _today;
  double? _fuelMonth;
  bool _busy = false;
  Timer? _statusTimer;
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus().then((_) => _refreshStats());
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshStatus());
    _statsTimer = Timer.periodic(const Duration(minutes: 1), (_) => _refreshStats());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    _statsTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus().then((_) => _refreshStats());
    }
  }

  Future<void> _refreshStatus() async {
    final s = await NativeBridge.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _refreshStats() async {
    final s = _status;
    if (s == null || s.logDir.isEmpty) return;
    final today = dayKey(DateTime.now());
    final stats = await loadDayStats(s.logDir, [today], openUntil: s.tracking ? DateTime.now() : null);
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month);
    final fuel = (await FuelStore(s.logDir).load())
        .where((e) => !e.date.isBefore(monthStart))
        .fold<double>(0, (sum, e) => sum + e.amount);
    if (!mounted) return;
    setState(() {
      _today = Totals([stats[today]!]);
      _fuelMonth = fuel;
    });
  }

  Future<void> _start() async {
    final s = _status;
    if (s == null) return;
    if (!s.a11yEnabled) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => OnBox(
            child: AlertDialog(
          backgroundColor: kBox,
          title: const Text('Ekran okuyucu kapalı'),
          content: const Text(
              'Martı ekranı okunamaz, teklifler kaydedilmez. Sadece konum ve süre kaydı başlar.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'settings'), child: const Text('Ayarlara git')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'start'), child: const Text('Yine de başlat')),
          ],
        )),
      );
      if (choice == 'settings') {
        _openSettings();
        return;
      }
      if (choice != 'start') return;
    }

    await Permission.notification.request();
    final loc = await Permission.locationWhenInUse.request();
    if (!loc.isGranted) {
      _snack('Konum izni olmadan başlatılamaz.');
      return;
    }
    await NativeBridge.startTracking();
    if (s.ocrOnStart && !s.capturing) {
      final ok = await NativeBridge.startCapture();
      if (!ok) _snack('Ekran kaydı izni verilmedi; OCR olmadan devam ediliyor.');
    }
  }

  Future<void> _stop() async {
    await NativeBridge.stopTracking();
    if (_status?.capturing == true) await NativeBridge.stopCapture();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_status?.tracking == true) {
        await _stop();
      } else {
        await _start();
      }
      await Future.delayed(const Duration(milliseconds: 500));
      await _refreshStatus();
      await _refreshStats();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))
        .then((_) => _refreshStatus());
  }

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) => _refreshStats());
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final dir = s?.logDir ?? '';
    final today = _today;
    final tracking = s?.tracking ?? false;
    final perHour = today?.perHour;

    final tiles = <Widget>[
      _StatButton(
        icon: Icons.payments_outlined,
        title: 'Kazanç',
        value: today == null ? '-' : 'Bugün ${money(today.earnings)}\n${today.tripCount} yolculuk',
        onTap: () => _open(EarningsPage(logDir: dir, tracking: tracking)),
      ),
      _StatButton(
        icon: Icons.route,
        title: 'Yol',
        value: today == null ? '-' : 'Bugün ${km(today.km)}\nMüşteriyle ${km(today.rideKm)}',
        onTap: () => _open(ActivityPage(logDir: dir, focus: ActivityFocus.distance, tracking: tracking)),
      ),
      _StatButton(
        icon: Icons.timer_outlined,
        title: 'Aktif süre',
        value: today == null
            ? '-'
            : 'Bugün ${duration(today.active)}${perHour == null ? '' : '\n${perHour.round()} TL/sa'}',
        onTap: () => _open(ActivityPage(logDir: dir, focus: ActivityFocus.time, tracking: tracking)),
      ),
      _StatButton(
        icon: Icons.local_gas_station_outlined,
        title: 'Yakıt',
        value: _fuelMonth == null ? '-' : 'Bu ay ${money(_fuelMonth)}',
        onTap: () => _open(FuelPage(logDir: dir)),
      ),
      _StatButton(
        icon: Icons.grid_on,
        title: 'Isı haritası',
        value: 'Gün × saat TL/saat',
        onTap: () => _open(HeatmapPage(logDir: dir)),
      ),
      _StatButton(
        icon: Icons.map_outlined,
        title: 'Yoğunluk haritası',
        value: 'Alış · bırakış · teklif noktaları',
        onTap: () => _open(DensityPage(logDir: dir)),
      ),
      _StatButton(
        icon: Icons.hourglass_bottom,
        title: 'Bölge analizi',
        value: 'Bıraktıktan sonra yeni müşteri süresi',
        onTap: () => _open(RegionPage(logDir: dir)),
      ),
      _StatButton(
        icon: Icons.request_quote_outlined,
        title: 'Teklifler ve müşteriler',
        value: today == null
            ? '-'
            : 'Bugün ${today.offerCount} teklif\n${today.acceptedCount} kabul',
        onTap: () => _open(OffersPage(logDir: dir)),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 36, semanticLabel: 'PY Stats'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: kBg,
            onSelected: (_) => _openSettings(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Ayarlar ve kurulum'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshStats,
              child: GridView.count(
                crossAxisCount: 2,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: tiles,
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: s == null ? null : _StartButton(status: s, busy: _busy, onPressed: _toggle),
    );
  }
}

class _StatButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _StatButton({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OnBox(
      child: Builder(
        builder: (context) => Material(
          color: kBox,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(icon, radius: 20),
                  const Spacer(),
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(value, style: TextStyle(color: context.muted, fontSize: 13), maxLines: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  final NativeStatus status;
  final bool busy;
  final VoidCallback onPressed;

  const _StartButton({required this.status, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final running = status.tracking;
    final started = status.trackingStartedAt;
    final label = running
        ? 'Durdur${started == null ? '' : ' · ${duration(DateTime.now().difference(started))}'}'
        : 'Başlat';
    return SizedBox(
      height: 64,
      child: FloatingActionButton.extended(
        onPressed: busy ? null : onPressed,
        backgroundColor: running ? kBox : kGreen,
        foregroundColor: kDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        icon: busy
            ? SizedBox(
                width: 22,
                height: 22,
                child: const CircularProgressIndicator(strokeWidth: 2.5, color: kDark),
              )
            : Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 30),
        label: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
