import 'package:flutter/material.dart';
import 'db.dart';

class AppTheme {
  final String name;
  final Color seed;
  final Color accent;
  const AppTheme(this.name, this.seed, this.accent);
}

const appThemes = <AppTheme>[
  AppTheme('Emerald', Color(0xFF00897B), Color(0xFF26A69A)),
  AppTheme('Indigo', Color(0xFF3F51B5), Color(0xFF5C6BC0)),
  AppTheme('Royal Violet', Color(0xFF6A1B9A), Color(0xFFAB47BC)),
  AppTheme('Sunset', Color(0xFFE65100), Color(0xFFFB8C00)),
  AppTheme('Rose', Color(0xFFC2185B), Color(0xFFEC407A)),
  AppTheme('Ocean', Color(0xFF0277BD), Color(0xFF29B6F6)),
  AppTheme('Forest', Color(0xFF2E7D32), Color(0xFF66BB6A)),
  AppTheme('Graphite', Color(0xFF37474F), Color(0xFF607D8B)),
];

class ThemeController extends ChangeNotifier {
  int themeIndex = 0;
  ThemeMode mode = ThemeMode.system;

  AppTheme get current => appThemes[themeIndex.clamp(0, appThemes.length - 1)];

  Future<void> load() async {
    final ti = await DB.settingGet('themeIndex');
    final md = await DB.settingGet('themeMode');
    if (ti != null) themeIndex = int.tryParse(ti) ?? 0;
    if (md != null) {
      mode = ThemeMode.values.firstWhere((m) => m.name == md, orElse: () => ThemeMode.system);
    }
    notifyListeners();
  }

  Future<void> setTheme(int i) async {
    themeIndex = i;
    await DB.settingSet('themeIndex', '$i');
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    mode = m;
    await DB.settingSet('themeMode', m.name);
    notifyListeners();
  }

  ThemeData _build(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: current.seed, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          b == Brightness.light ? const Color(0xFFF6F8FA) : scheme.surface,
      cardTheme: CardTheme(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        color: b == Brightness.light ? Colors.white : scheme.surfaceContainerHigh,
      ),
      appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        backgroundColor: b == Brightness.light ? Colors.white : scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }

  ThemeData get light => _build(Brightness.light);
  ThemeData get dark => _build(Brightness.dark);
}

final theme = ThemeController();

/// Header gradient used across screens.
LinearGradient headerGradient(BuildContext context) {
  final t = theme.current;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [t.seed, t.accent],
  );
}
