import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/calendar_screen.dart';
import 'screens/chart_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja');
  runApp(const ProviderScope(child: MindStockApp()));
}

class MindStockApp extends StatelessWidget {
  const MindStockApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ローソク足が主役なので、チャートの視認性を最優先にした
    // ダーク基調の配色（仕様書 §8）。
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF26A69A),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'MindStock',
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeShell(),
    );
  }
}

/// ボトムナビゲーション。ダッシュボードを玄関にし、
/// 入力はダッシュボードのクイック入力から（最速・最低ハードル）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      // ミニチャートのタップでチャートタブへ
      DashboardScreen(onOpenChart: () => setState(() => _index = 1)),
      const ChartScreen(),
      const CalendarScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.candlestick_chart_outlined),
            selectedIcon: Icon(Icons.candlestick_chart),
            label: 'チャート',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '一覧',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
