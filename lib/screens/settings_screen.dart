import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/monetization.dart';
import '../l10n.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../widgets/points_sheet.dart';

/// 設定画面。iOS風のグループセクションで構成する。
///
/// - ポイント: 残高と補充（広告 / 課金）
/// - アカウント: Googleログイン、Driveへのバックアップ/復元
/// - 音声入力: Whisper（OpenAI APIキー・任意）
/// - データ: 全削除
///
/// AI解析は開発者のキーを持つサーバー経由（ポイント制）で行うため、
/// ユーザーがAI解析キーを入力する項目は無い。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  GoogleSignInAccount? _account;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 前回のGoogleログインを復元。
    // signInSilently自体が例外を投げない実装だが、念のため二重にガードし、
    // 設定画面を開いただけで（何も操作していないのに）落ちることがないようにする。
    ref
        .read(backupServiceProvider)
        .signInSilently()
        .then((account) {
          if (mounted) setState(() => _account = account);
        })
        .catchError((_) {
          // 復元に失敗しても未ログイン状態として扱うだけ。ユーザーには
          // 何も表示しない（明示的にログインボタンを押した時だけエラーを見せる）。
        });
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
    final i18n = context.i18n;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          FadeSlideIn(child: _pointsSection(context)),
          const SizedBox(height: 20),
          FadeSlideIn(delayMs: 40, child: _accountSection(context)),
          const SizedBox(height: 20),
          FadeSlideIn(delayMs: 120, child: _voiceSection(context)),
          const SizedBox(height: 20),
          FadeSlideIn(delayMs: 180, child: _dataSection(context)),
          const SizedBox(height: 40),
          FadeSlideIn(
            delayMs: 240,
            child: Center(
              child: Text(
                i18n.tr('app_tagline'),
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

  /// 最終バックアップ日時の表示（自動・手動共通）。
  /// 7日以上経つと自動でバックアップされる旨も添える。
  Widget _lastBackupLine(BuildContext context) {
    final i18n = context.i18n;
    final iso = ref.watch(lastBackupAtProvider).valueOrNull ?? '';
    final at = DateTime.tryParse(iso);
    final text = at == null
        ? i18n.tr('empty_point')
        : i18n.tr(
            'last_backup',
            args: {
              'time': i18n.date(
                at,
                jaPattern: 'M/d HH:mm',
                enPattern: 'MMM d, HH:mm',
              ),
            },
          );
    return Row(
      children: [
        Icon(Icons.schedule_rounded, size: 13, color: AppColors.inkSoft),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }

  // ── ポイント ─────────────────────────────────────────

  Widget _pointsSection(BuildContext context) {
    final i18n = context.i18n;
    final points = ref.watch(pointsProvider).valueOrNull ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, Icons.stars_rounded, i18n.tr('points')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '◆ $points',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppColors.accent,
                      ),
                    ),
                    Text(
                      i18n.tr(
                        'analysis_cost',
                        args: {'cost': Monetization.analysisCost.toString()},
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => showPointsSheet(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(i18n.tr('add_points')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── アカウント ────────────────────────────────────────

  Widget _accountSection(BuildContext context) {
    final i18n = context.i18n;
    final account = _account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, Icons.person_outline_rounded, i18n.tr('account')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (account == null) ...[
                  Text(
                    i18n.tr('google_login_help'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.inkSoft,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: Text(i18n.tr('google_login')),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final result = await ref
                                .read(backupServiceProvider)
                                .signIn();
                            setState(() => _account = result);
                            if (result != null) _toast(i18n.tr('no_login_toast'));
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
                              account.displayName ?? i18n.tr('google_account'),
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
                                await ref.read(backupServiceProvider).signOut();
                                setState(() => _account = null);
                              }),
                        child: Text(i18n.tr('logout')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(
                            Icons.cloud_upload_outlined,
                            size: 18,
                          ),
                          label: Text(i18n.tr('backup')),
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  final entries =
                                      ref
                                          .read(entriesProvider)
                                          .valueOrNull
                                          ?.values ??
                                      const [];
                                  await ref
                                      .read(backupServiceProvider)
                                      .backup(entries);
                                  // 自動バックアップと共通のタイムスタンプを更新
                                  await ref
                                      .read(lastBackupAtProvider.notifier)
                                      .save(DateTime.now().toIso8601String());
                                  HapticFeedback.mediumImpact();
                                  _toast(i18n.tr('backed_up'));
                                }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(
                            Icons.cloud_download_outlined,
                            size: 18,
                          ),
                          label: Text(i18n.tr('restore')),
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
                                  _toast(
                                    i18n.tr('restored_count', args: {
                                      'count': count.toString(),
                                    }),
                                  );
                                }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _lastBackupLine(context),
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

  // ── 音声入力 ─────────────────────────────────────────

  Widget _voiceSection(BuildContext context) {
    final available = ref.watch(voiceInputAvailableProvider);
    final i18n = context.i18n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, Icons.mic_none_rounded, i18n.tr('voice')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _statusDot(available),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    available
                        ? i18n.tr('voice_help_on')
                        : i18n.tr('voice_help_off'),
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
    final i18n = context.i18n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, Icons.storage_rounded, i18n.tr('data')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.bear),
            title: Text(
              context.i18n.tr('delete_all'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.bear,
              ),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _confirmClear(context),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final i18n = context.i18n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n.tr('delete_all_confirm_title')),
        content: Text(i18n.tr('delete_all_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(i18n.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.bear),
            onPressed: () => Navigator.pop(context, true),
            child: Text(i18n.tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(entriesProvider.notifier).clearAll();
    _toast(i18n.tr('delete_done'));
  }
}
