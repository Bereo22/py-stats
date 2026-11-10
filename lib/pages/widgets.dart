import 'package:flutter/material.dart';

import '../data/periods.dart';
import '../theme.dart';

class PeriodPicker extends StatelessWidget {
  final Period value;
  final ValueChanged<Period> onChanged;
  const PeriodPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SegmentedButton<Period>(
        segments: [for (final p in Period.values) ButtonSegment(value: p, label: Text(p.label))],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

/// Big headline number with detail rows underneath.
class SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final List<Widget> rows;
  const SummaryCard({super.key, required this.label, required this.value, required this.rows});

  @override
  Widget build(BuildContext context) => Box(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: kBoxMuted)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(12)),
                child: Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: kDark)),
              ),
              const SizedBox(height: 16),
              ...rows,
            ],
          ),
        ),
      );
}

class StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool indent;
  const StatRow(this.label, this.value, {super.key, this.indent = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 4, bottom: 4, left: indent ? 14 : 0),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: context.muted))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}

class Note extends StatelessWidget {
  final String text;
  const Note(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(text, style: const TextStyle(color: kMuted, fontSize: 12)),
      );
}

/// One horizontal bar per day, newest on top.
class DayBars extends StatelessWidget {
  final List<String> days;
  final double Function(String day) value;
  final String Function(String day) label;
  const DayBars({super.key, required this.days, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final maxV = days.map(value).fold<double>(0, (a, b) => b > a ? b : a);
    const barH = 150.0;

    Widget column(String d, double w) {
      final v = value(d);
      return SizedBox(
        width: w,
        child: Column(
          children: [
            SizedBox(
              height: 16,
              child: v <= 0
                  ? null
                  : FittedBox(fit: BoxFit.scaleDown, child: Text(label(d), style: const TextStyle(fontSize: 11))),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: barH,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: w * 0.62,
                  height: v <= 0 || maxV == 0 ? 2 : barH * v / maxV,
                  decoration: BoxDecoration(
                    color: v <= 0 ? const Color(0x33FFFFFF) : kGreen,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(weekdayShort[parseDayKey(d).weekday - 1], style: const TextStyle(color: kMuted, fontSize: 11)),
            Text(d.substring(8), style: const TextStyle(color: kMuted, fontSize: 11)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (_, c) {
        if (days.length <= 10) {
          final w = c.maxWidth / days.length;
          return Row(children: [for (final d in days) column(d, w)]);
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(children: [for (final d in days) column(d, 44)]),
        );
      },
    );
  }
}

const loading = Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
