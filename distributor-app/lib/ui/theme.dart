import 'package:material_ui/material_ui.dart';

/// Al-Kaif Al-Asli palette (from the logo)
class KaifColors {
  static const green = Color(0xFF1F3B2C);
  static const leaf = Color(0xFF52B051);
  static const cream = Color(0xFFFFF9EB);
  static const danger = Color(0xFFB3261E);
}

ThemeData kaifTheme({String? fontFamily}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: KaifColors.green,
    primary: KaifColors.green,
    secondary: KaifColors.leaf,
    surface: Colors.white,
  );
  return ThemeData(
    fontFamily: fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: KaifColors.cream,
    appBarTheme: const AppBarTheme(backgroundColor: KaifColors.green, foregroundColor: Colors.white),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), textStyle: TextStyle(fontSize: 16, fontFamily: fontFamily)),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
    cardTheme: const CardThemeData(color: Colors.white, margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
  );
}

String money(int halalas) {
  final neg = halalas < 0;
  final a = halalas.abs();
  var w = (a ~/ 100).toString();
  final b = StringBuffer();
  for (var i = 0; i < w.length; i++) {
    if (i > 0 && (w.length - i) % 3 == 0) b.write(',');
    b.write(w[i]);
  }
  return '${neg ? '-' : ''}$b.${(a % 100).toString().padLeft(2, '0')}';
}
