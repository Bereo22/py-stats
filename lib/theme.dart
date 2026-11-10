import 'package:flutter/material.dart';

const kGreen = Color(0xFFBADF30);
const kBg = Color(0xFF68736D);
const kBox = Color(0xFFA9AFAA);
const kDark = Color(0xFF262626);
const kWhite = Color(0xFFFFFFFF);

/// Secondary text on the background.
const kMuted = Color(0xC7FFFFFF);

/// Secondary text on boxes.
const kBoxMuted = Color(0xBF262626);

extension ThemeColors on BuildContext {
  /// Secondary text color for wherever this widget sits: background or box.
  Color get muted => Theme.of(this).colorScheme.onSurfaceVariant;
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: kGreen,
    onPrimary: kDark,
    secondary: kGreen,
    onSecondary: kDark,
    secondaryContainer: kGreen,
    onSecondaryContainer: kDark,
    surface: kBg,
    onSurface: kWhite,
    onSurfaceVariant: kMuted,
    outline: Color(0x99FFFFFF),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    canvasColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kWhite,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardTheme(
      color: kBox,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kDark : kWhite),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kGreen : kBg),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kGreen,
        foregroundColor: kDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kGreen,
      foregroundColor: kDark,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kGreen),
    dividerColor: Colors.white24,
  );
}

/// Theme for content drawn on a [kBox] surface: dark text instead of white.
ThemeData boxTheme(ThemeData base) {
  final scheme = base.colorScheme.copyWith(
    surface: kBox,
    onSurface: kDark,
    onSurfaceVariant: kBoxMuted,
    primary: kDark,
    onPrimary: kGreen,
    outline: kBoxMuted,
  );
  return base.copyWith(
    colorScheme: scheme,
    canvasColor: kBox,
    textTheme: base.textTheme.apply(bodyColor: kDark, displayColor: kDark),
    iconTheme: const IconThemeData(color: kDark),
    listTileTheme: const ListTileThemeData(textColor: kDark, iconColor: kDark),
    dividerColor: Colors.black26,
    switchTheme: base.switchTheme.copyWith(
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kGreen : kBg),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: kDark)),
    inputDecorationTheme: const InputDecorationTheme(
      labelStyle: TextStyle(color: kBoxMuted),
      floatingLabelStyle: TextStyle(color: kDark),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: kBoxMuted)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kDark, width: 2)),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: kDark),
  );
}

/// Applies [boxTheme] to everything below.
class OnBox extends StatelessWidget {
  final Widget child;
  const OnBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Theme(data: boxTheme(Theme.of(context)), child: child);
}

/// Dark icon on a green dot (dimmed when not [active]); reads well on boxes.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final bool active;
  final double radius;
  const IconBadge(this.icon, {super.key, this.active = true, this.radius = 18});

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: active ? kGreen : Colors.black12,
        child: Icon(icon, color: active ? kDark : kBoxMuted, size: radius * 1.1),
      );
}

/// Card in the box color with dark content.
class Box extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  const Box({super.key, required this.child, this.margin, this.onTap});

  @override
  Widget build(BuildContext context) => OnBox(
        child: Card(
          margin: margin,
          clipBehavior: onTap == null ? Clip.none : Clip.antiAlias,
          child: onTap == null ? child : InkWell(onTap: onTap, child: child),
        ),
      );
}
