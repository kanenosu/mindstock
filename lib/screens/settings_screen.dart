import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// 設定画面。Claude APIキーの登録のみ（MVP最小限）。
/// キー未設定でも簡易解析で動くため、必須ではない。
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
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('AI解析 (Claude API)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            apiKey.isEmpty
                ? '未設定: 簡易キーワード解析で動作中です。APIキーを設定すると、'
                      '文脈を読んだ採点（快楽順応・損失回避込み）になります。'
                : 'Claude APIで解析中です。',
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
              await ref
                  .read(apiKeyProvider.notifier)
                  .save(_controller.text);
              _controller.clear();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('保存しました')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
