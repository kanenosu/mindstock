import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/calendar_screen.dart';
import 'screens/chart_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/entry_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja');
  runApp(const ProviderScope(child: MindStockApp()));
}

class MindStockApp extends StatelessWidget {
  const MindStockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindStock',
      theme: buildAppTheme(),
      scrollBehavior: const _BouncyScrollBehavior(),
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

/// ボトムナビゲーション: ホーム / 日記 / 推移 / 記録 / 設定。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _tabCount = 5;

  int _index = 0;

  void _goTo(int i) {
    if (i < 0 || i >= _tabCount) return;
    // 日記のテキスト欄のフォーカス・選択ハンドルが
    // 他のタブに残らないよう、切替時に必ず解除する
    FocusManager.instance.primaryFocus?.unfocus();
    if (i != _index) HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        onOpenChart: () => _goTo(2),
        onOpenDiary: () => _goTo(1),
      ),
      const EntryScreen(),
      const ChartScreen(),
      const CalendarScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      // 横スワイプでもタブを切り替えられるようにする。
      // 内側のチャート（ピンチズーム・横ドラッグ）は子ウィジェットの
      // ジェスチャーが先に処理されるため、ここでは奪わない。
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          const threshold = 250.0;
          if (velocity < -threshold) {
            _goTo(_index + 1); // 左スワイプ → 次のタブ
          } else if (velocity > threshold) {
            _goTo(_index - 1); // 右スワイプ → 前のタブ
          }
        },
        child: IndexedStack(index: _index, children: screens),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTo,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_outlined),
            selectedIcon: Icon(Icons.edit),
            label: '日記',
          ),
          NavigationDestination(
            icon: Icon(Icons.candlestick_chart_outlined),
            selectedIcon: Icon(Icons.candlestick_chart),
            label: '推移',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: '記録',
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

/// iPhone風のバウンススクロールを全画面に適用する。
class _BouncyScrollBehavior extends MaterialScrollBehavior {
  const _BouncyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}
