import 'package:flutter/material.dart';

import '../data/day_stats.dart';
import '../data/log_reader.dart';
import '../format.dart';
import '../parsing/offer_parser.dart';
import '../parsing/trip_parser.dart';
import '../theme.dart';
import 'day_dropdown.dart';
import 'trip_page.dart';

class OffersPage extends StatefulWidget {
  final String logDir;
  const OffersPage({super.key, required this.logDir});

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  List<String> _days = [];
  String? _day;
  Map<String, DayStats>? _stats;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final days = await LogReader(widget.logDir).days();
    final stats = await loadDayStats(widget.logDir, days);
    if (!mounted) return;
    setState(() {
      _days = days;
      _day = days.isEmpty ? null : days.first;
      _stats = stats;
    });
  }

  List<TripStat> get trips => _stats == null || _day == null ? const [] : _stats![_day]!.trips;

  void _openTrip(TripStat s) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => TripPage(logDir: widget.logDir, stat: s)));

  void _showCustomer(CustomerStats c, Map<Trip, TripStat> stats) {
    final trips = [...c.trips]..sort((a, b) => b.acceptedAt.compareTo(a.acceptedAt));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kBox,
      builder: (ctx) => OnBox(
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('${c.key} · ${c.count} yolculuk · ${money(c.total)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              for (final t in trips)
                ListTile(
                  leading: const IconBadge(Icons.route),
                  title: Text('${t.acceptedAt.day}.${two(t.acceptedAt.month)} ${hhmm(t.acceptedAt)} · ${money(t.price)}'),
                  subtitle: Text(
                    [t.pickupAddress, t.dropoffAddress].whereType<String>().join('  →  '),
                    style: const TextStyle(color: kBoxMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: stats[t] == null
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _openTrip(stats[t]!);
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final offers = stats == null || _day == null ? const <Offer>[] : stats[_day]!.offers;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Teklifler'),
          actions: [DayDropdown(days: _days, value: _day, onChanged: (d) => setState(() => _day = d))],
          bottom: const TabBar(
            indicatorColor: kGreen,
            labelColor: kWhite,
            unselectedLabelColor: kMuted,
            tabs: [Tab(text: 'Teklifler'), Tab(text: 'Müşteriler')],
          ),
        ),
        body: stats == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                _offerList(offers),
                _customerList(stats.values.expand((d) => d.trips).toList()),
              ]),
      ),
    );
  }

  Widget _offerList(List<Offer> offers) {
    if (offers.isEmpty) {
      return const _Empty('Bu gün için teklif algılanmadı.\n'
          'Ham ekran kayıtlarında "Kabul et" ekranı görünüyorsa okuma kurallarını güncelleriz.');
    }
    final accepted = offers.where((o) => o.accepted).length;
    final canceled = offers.where((o) => o.canceled).length;
    final trips = {for (final s in this.trips) s.trip.offer: s};
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            '${offers.length} teklif · $accepted kabul edildi${canceled == 0 ? '' : ', $canceled tanesi sonra iptal oldu'}',
            style: const TextStyle(color: kMuted),
          ),
        ),
        for (final o in offers.reversed)
          _OfferCard(o, trips[o], onTap: trips[o] == null ? null : () => _openTrip(trips[o]!)),
      ],
    );
  }

  Widget _customerList(List<TripStat> all) {
    final stats = {for (final s in all) s.trip: s};
    final customers = TripParser.customers(all.map((s) => s.trip));
    if (customers.isEmpty) return const _Empty('Henüz tamamlanan yolculuk yok.');
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            'Tüm kayıtlardaki yolculuklar. Martı sadece baş harf ve puan gösterdiği için '
            'aynı baş harf ve puana sahip farklı kişiler birleşebilir; puan değişince aynı kişi ayrı görünebilir.',
            style: TextStyle(color: kMuted, fontSize: 12),
          ),
        ),
        for (final c in customers)
          Box(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: kGreen,
                child: Text('${c.count}', style: const TextStyle(color: kDark, fontWeight: FontWeight.w700)),
              ),
              title: Text(c.key),
              subtitle: Text(
                'Son: ${c.last.day}.${two(c.last.month)} ${hhmm(c.last)}',
                style: const TextStyle(color: kBoxMuted),
              ),
              trailing: Text(money(c.total), style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => _showCustomer(c, stats),
            ),
          ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  final Offer o;
  final TripStat? stat;
  final VoidCallback? onTap;
  const _OfferCard(this.o, this.stat, {this.onTap});

  String get _outcome {
    if (!o.accepted) return 'kabul edilmedi';
    if (o.canceled) return 'kabul edildi, sonra ${(stat?.trip.canceledBy ?? CancelBy.unknown).label.toLowerCase()}';
    return 'kabul edildi · rota için dokun';
  }

  @override
  Widget build(BuildContext context) {
    final perKm = o.tlPerKm;
    return Box(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(hhmmss(o.firstSeen), style: const TextStyle(color: kBoxMuted)),
                const SizedBox(width: 8),
                if (o.customerInitials != null || o.customerRating != null) Text(o.customerKey),
                const Spacer(),
                if (o.accepted)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: o.canceled
                        ? const Icon(Icons.cancel, color: kBoxMuted, size: 22)
                        : const IconBadge(Icons.check, radius: 11),
                  ),
                Text(
                  money(o.price),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    decoration: o.canceled ? TextDecoration.lineThrough : null,
                    color: o.canceled ? kBoxMuted : kDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _leg(Icons.person_pin_circle, kBoxMuted, o.pickupMin, o.pickupKm, o.pickupAddress),
            const SizedBox(height: 4),
            _leg(Icons.place, kDark, o.tripMin, o.tripKm, o.dropoffAddress),
            const SizedBox(height: 8),
            Text(
              [
                _outcome,
                if (o.payment != null) o.payment!,
                if (perKm != null) '${perKm.toStringAsFixed(1)} TL/km',
                'ekranda ${o.shownFor.inSeconds} sn',
              ].join(' · '),
              style: const TextStyle(color: kBoxMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leg(IconData icon, Color color, int? min, double? distance, String? address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${min ?? '-'} dk · ${km(distance)}${address == null ? '' : '\n$address'}',
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
        ),
      );
}
