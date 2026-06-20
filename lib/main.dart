import 'package:flutter/material.dart';
import 'db.dart';
import 'branding.dart';
import 'cloud.dart';
import 'lock.dart';
import 'screens/security.dart';
import 'pro.dart';
import 'theme.dart';
import 'screens/budgets.dart';
import 'screens/home.dart';
import 'screens/more.dart';
import 'screens/analytics.dart';
import 'screens/txns.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WalletApp());
}

class WalletApp extends StatefulWidget {
  const WalletApp({super.key});
  @override
  State<WalletApp> createState() => _WalletAppState();
}

class _WalletAppState extends State<WalletApp> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await DB.db; // ensure migration runs
    await theme.load();
    await pro.load();
    await branding.load();
    await cloud.init(); // optional Firebase cloud backup (safe if offline)
    await lock.load(); // app lock state
    await DB.runRecurring(); // post any due recurring payments
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: theme,
      builder: (_, __) => MaterialApp(
        title: 'Wallet Pro',
        debugShowCheckedModeBanner: false,
        theme: theme.light,
        darkTheme: theme.dark,
        themeMode: theme.mode,
        home: const LockGate(child: Shell()),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;

  @override
  void initState() {
    super.initState();
    tryAutoBackup();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: i, children: const [
        HomeScreen(),
        TxnsScreen(),
        AnalyticsScreen(),
        BudgetsScreen(),
        MoreScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => setState(() => i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Records'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Analytics'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Budgets'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
        ],
      ),
    );
  }
}
