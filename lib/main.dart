import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'theme.dart';

void main() {
  runApp(const TagStatsApp());
}

class TagStatsApp extends StatelessWidget {
  const TagStatsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PY Stats',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomePage(),
    );
  }
}
