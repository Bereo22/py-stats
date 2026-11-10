import 'package:flutter/material.dart';

import '../theme.dart';

class DayDropdown extends StatelessWidget {
  final List<String> days;
  final String? value;
  final ValueChanged<String> onChanged;

  const DayDropdown({super.key, required this.days, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: DropdownButton<String>(
        value: value,
        dropdownColor: kBg,
        underline: const SizedBox.shrink(),
        items: [for (final d in days) DropdownMenuItem(value: d, child: Text(d))],
        onChanged: (d) {
          if (d != null) onChanged(d);
        },
      ),
    );
  }
}
