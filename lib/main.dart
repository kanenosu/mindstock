import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'providers.dart';
import 'screens/calendar_screen.dart';
import 'screens/chart_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/entry_screen.dart';
import 'screens/onboarding_screen.dart';
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
      // 「温かいクリーム基調」がこのアプリのアイデンティティなので、
      // 端末がダークモードでも常にライトテーマで表示する（意図的な固定・改善点§4）。
      // 端末のダーク設定に引きずられて中途半端に暗転しないよう明示する。
      themeMode: ThemeMode.light,
      scrollBehavior: const _BouncyScrollBehavior(),
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _RootGate(),
    );
  }
}

/// 初回起動ならチュートリアル、以後はホームへ。切替はクロスフェード。
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = ref.watch(onboardingDoneProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: switch (done.valueOrNull) {
        null => const ColoredBox(
          key: ValueKey('loading'),
          color: AppColors.cream,
        ),
        false => const OnboardingScreen(key: ValueKey('onboarding')),
        true => const HomeShell(key: ValueKey('home')),
      },
    );
  }
}

/// ボトムナビゲーション: ホーム / 日記 / 推移 / 記録 / 設定。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _tabCount = 5;

  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 起動時の自動バックアップ（ログイン済み & 前回から7日以上経過時のみ）。
    // 第一フレーム後に静かに走らせる（改善点§6）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeAutoBackup(ref);
    });
  }

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
      DashboardScreen(onOpenChart: () => _goTo(2), onOpenDiary: () => _goTo(1)),
      const EntryScreen(),
      const ChartScreen(),
      const CalendarScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      // 横スワイプでもタブを切り替えられるようにする。
      // 推移タブ(index 2)ではハンドラ自体を外して認識器を登録しない —
      // 親のドラッグ認識がチャートのピンチ/パンを奪ってしまうため。
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: _index == 2
            ? null
            : (details) {
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
