import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// 設定画面。
///
/// - AI解析モードの切り替え（デモ解析 / Claude API — 当面はデモが既定）
/// - Claude APIキーの登録
/// - デモデータの投入・全データ削除
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apiKey = ref.watch(apiKeyProvider).valueOrNull ?? '';
    final mode = ref.watch(analyzerModeProvider).valueOrNull ?? AnalyzerMode.demo;

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('AI解析', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<AnalyzerMode>(
            segments: [
              for (final m in AnalyzerMode.values)
                ButtonSegment(value: m, label: Text(m.label)),
            ],
            selected: {mode},
            onSelectionChanged: (s) =>
                ref.read(analyzerModeProvider.notifier).setMode(s.first),
          ),
          const SizedBox(height: 8),
          Text(
            switch (mode) {
              AnalyzerMode.demo =>
                'デモ解析で動作中。API不要で、文の抽出と擬似採点'
                    '（快楽順応・損失回避のシミュレート込み）を行います。',
              AnalyzerMode.api => apiKey.isEmpty
                  ? 'Claude APIモードですが、キーが未設定のためデモ解析で動作します。'
                        '下にAPIキーを入力してください。'
                  : 'Claude APIで解析中。文脈を読んだ採点になります。',
            },
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Claude API キー',
              hintText: apiKey.isEmpty ? 'sk-ant-...' : '設定済み（変更する場合のみ入力）',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await ref.read(apiKeyProvider.notifier).save(_controller.text);
              _controller.clear();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('保存しました')),
                );
              }
            },
            child: const Text('APIキーを保存'),
          ),
          const Divider(height: 48),
          Text('デモデータ', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '過去約4ヶ月分のサンプル日記（どん底の谷とそこからの回復の軌跡入り）を投入して、'
            'チャートの動きを確認できます。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_graph),
            label: const Text('デモデータを投入'),
            onPressed: () => _confirmSeed(context),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            label: const Text('全データを削除'),
            onPressed: () => _confirmClear(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSeed(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('デモデータを投入しますか？'),
        content: const Text('過去約4ヶ月分のサンプル日記を追加します。'
            '同じ日付の既存データは上書きされます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('投入'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(entriesProvider.notifier).seedDemoData();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('デモデータを投入しました。チャートを見てみてください')),
      );
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('全データを削除しますか？'),
        content: const Text('すべての日記と出来事が消えます。この操作は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(entriesProvider.notifier).clearAll();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('全データを削除しました')),
      );
    }
  }
}
