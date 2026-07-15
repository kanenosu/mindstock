import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../providers.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../widgets/pill_selector.dart';

/// 設定画面。iOS風のグループセクションで構成する。
///
/// - アカウント: Googleログイン、Driveへのバックアップ/復元
/// - AI解析: プロバイダー選択（Claude / ChatGPT）+ 各APIキー
/// - 音声入力: Whisper（OpenAIキーを共用）
/// - データ: サンプル投入・全削除
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _claudeController = TextEditingController();
  final _openAiController = TextEditingController();

  GoogleSignInAccount? _account;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 前回のGoogleログインを復元
    ref.read(backupServiceProvider).signInSilently().then((account) {
      if (mounted) setState(() => _account = account);
    });
  }

  @override
  void dispose() {
    _claudeController.dispose();
    _openAiController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final claudeKey = ref.watch(apiKeyProvider).valueOrNull ?? '';
    final openAiKey = ref.watch(openAiApiKeyProvider).valueOrNull ?? '';
    final provider =
        ref.watch(aiProviderProvider).valueOrNull ?? AiProvider.claude;

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          FadeSlideIn(child: _accountSection(context)),
          const SizedBox(height: 20),
          FadeSlideIn(
            delayMs: 60,
            child: _aiSection(context, provider, claudeKey, openAiKey),
          ),
          const SizedBox(height: 20),
          FadeSlideIn(delayMs: 120, child: _voiceSection(context, openAiKey)),
          const SizedBox(height: 20),
          FadeSlideIn(delayMs: 180, child: _dataSection(context)),
          const SizedBox(height: 40),
          FadeSlideIn(
            delayMs: 240,
            child: Center(
              child: Text(
                'MindStock v0.1.0\nあなたの毎日は、記録するだけで資産になる。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  height: 1.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── セクション共通パーツ ──────────────────────────────

  Widget _sectionHeader(BuildContext context, IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.inkSoft),
          const SizedBox(width: 6),
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusDot(bool active) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: active ? AppColors.bull : AppColors.ink.withValues(alpha: 0.2),
      shape: BoxShape.circle,
    ),
  );

  // ── アカウント ────────────────────────────────────────

  Widget _accountSection(BuildContext context) {
    final account = _account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, Icons.person_outline_rounded, 'アカウント'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (account == null) ...[
                  Text(
                    'Googleでログインすると、日記データをGoogle Drive'
                    '（このアプリ専用の領域）にバックアップできます。'
                    '機種変更やアンインストール後の復元に。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.inkSoft,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Googleでログイン'),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final result = await ref
                                .read(backupServiceProvider)
                                .signIn();
                            setState(() => _account = result);
                            if (result != null) _toast('ログインしました');
                          }),
                  ),
                ] else ...[
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.cream,
                        backgroundImage: account.photoUrl != null
                            ? NetworkImage(account.photoUrl!)
                            : null,
                        child: account.photoUrl == null
                            ? const Icon(Icons.person, color: AppColors.ink)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account.displayName ?? 'Googleアカウント',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              account.email,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await ref
                                    .read(backupServiceProvider)
                                    .signOut();
                                setState(() => _account = null);
                              }),
                        child: const Text('ログアウト'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.cloud_upload_outlined,
                              size: 18),
                          label: const Text('バックアップ'),
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  final entries = ref
                                          .read(entriesProvider)
                                          .valueOrNull
                                          ?.values ??
                                      const [];
                                  await ref
                                      .read(backupServiceProvider)
                                      .backup(entries);
                                  HapticFeedback.mediumImpact();
                                  _toast('Driveにバックアップしました');
                                }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.cloud_download_outlined,
                              size: 18),
                          label: const Text('復元'),
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  final restored = await ref
                                      .read(backupServiceProvider)
                                      .restore();
                                  final count = await ref
                                      .read(entriesProvider.notifier)
                                      .importEntries(restored);
                                  HapticFeedback.mediumImpact();
                                  _toast('$count件の記録を復元しました');
                                }),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── AI解析 ───────────────────────────────────────────

  Widget _aiSection(
    BuildContext context,
    AiProvider provider,
    String claudeKey,
    String openAiKey,
  ) {
    final activeKeySet = switch (provider) {
      AiProvider.claude => claudeKey.isNotEmpty,
      AiProvider.openai => openAiKey.isNotEmpty,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, Icons.auto_awesome_outlined, 'AI解析'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PillSelector<AiProvider>(
                  items: AiProvider.values,
                  selected: provider,
                  labelOf: (p) => p.label,
                  onChanged: (p) =>
                      ref.read(aiProviderProvider.notifier).setProvider(p),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _statusDot(activeKeySet),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        activeKeySet
                            ? '${provider.label} で解析中。文脈を読んだ採点になります。'
                            : 'キー未設定のため、端末内の簡易解析で動作中です。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _keyField(
                  controller: _claudeController,
                  label: 'Claude API キー',
                  isSet: claudeKey.isNotEmpty,
                  hint: 'sk-ant-...',
                  onSave: (v) => ref.read(apiKeyProvider.notifier).save(v),
                ),
                const SizedBox(height: 10),
                _keyField(
                  controller: _openAiController,
                  label: 'OpenAI API キー（ChatGPT / 音声入力 共用）',
                  isSet: openAiKey.isNotEmpty,
                  hint: 'sk-...',
                  onSave: (v) =>
                      ref.read(openAiApiKeyProvider.notifier).save(v),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _keyField({
    required TextEditingController controller,
    required String label,
    required bool isSet,
    required String hint,
    required Future<void> Function(String) onSave,
  }) {
    return TextField(
      controller: controller,
      obscureText: true,
      decoration: InputDecoration(
        labelText: label,
        hintText: isSet ? '設定済み（変更する場合のみ入力）' : hint,
        suffixIcon: IconButton(
          icon: const Icon(Icons.save_outlined, size: 20),
          tooltip: '保存',
          onPressed: () async {
            if (controller.text.trim().isEmpty) return;
            await onSave(controller.text);
            controller.clear();
            HapticFeedback.selectionClick();
            _toast('保存しました');
          },
        ),
      ),
    );
  }

  // ── 音声入力 ─────────────────────────────────────────

  Widget _voiceSection(BuildContext context, String openAiKey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, Icons.mic_none_rounded, '音声入力（Whisper）'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _statusDot(openAiKey.isNotEmpty),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    openAiKey.isNotEmpty
                        ? '使えます。日記のマイクをタップ（または長押し）して話すと、文字起こしされて本文に追記されます。'
                        : '上のOpenAI APIキーを設定すると、日記のマイクから話して書けるようになります。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.inkSoft,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── データ ───────────────────────────────────────────

  Widget _dataSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, Icons.storage_rounded, 'データ'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.auto_graph, color: AppColors.ink),
                title: const Text(
                  'サンプルデータを投入',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  '谷と回復の軌跡入り・約4ヶ月分',
                  style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _confirmSeed(context),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.bear,
                ),
                title: const Text(
                  '全データを削除',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.bear,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _confirmClear(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmSeed(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('サンプルデータを投入しますか？'),
        content: const Text(
          '過去約4ヶ月分のサンプル日記を追加します。'
          '同じ日付の既存データは上書きされます。',
        ),
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
    _toast('サンプルデータを投入しました。チャートを見てみてください');
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.bear),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(entriesProvider.notifier).clearAll();
    _toast('全データを削除しました');
  }
}
