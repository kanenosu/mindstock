import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/monetization.dart';
import '../providers.dart';
import '../theme.dart';

/// ポイント補充シートを開く。
Future<void> showPointsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _PointsSheet(),
  );
}

/// ポイントの残高表示 + 補充シートを開くチップ（各画面のAppBarに置く）。
class PointsChip extends ConsumerWidget {
  const PointsChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(pointsProvider).valueOrNull ?? 0;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: AppColors.card,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showPointsSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('◆', style: TextStyle(color: AppColors.accent)),
                const SizedBox(width: 4),
                Text(
                  '$points',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.add, size: 15, color: AppColors.inkSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PointsSheet extends ConsumerStatefulWidget {
  const _PointsSheet();

  @override
  ConsumerState<_PointsSheet> createState() => _PointsSheetState();
}

class _PointsSheetState extends ConsumerState<_PointsSheet> {
  bool _watchingAd = false;

  @override
  void initState() {
    super.initState();
    // 広告を先読みしておく（表示までの待ちを減らす）。
    ref.read(rewardedAdServiceProvider).preload();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _watchAd() async {
    setState(() => _watchingAd = true);
    try {
      final earned = await ref.read(rewardedAdServiceProvider).showAndEarn();
      if (earned) {
        await ref.read(pointsProvider.notifier).add(Monetization.rewardPerAd);
        HapticFeedback.mediumImpact();
        _toast('${Monetization.rewardPerAd}ポイント獲得しました');
      } else {
        _toast('広告の準備中です。少し待ってからもう一度お試しください');
      }
    } finally {
      if (mounted) setState(() => _watchingAd = false);
    }
  }

  Future<void> _buy(ProductDetails product) async {
    try {
      await ref.read(iapServiceProvider).buy(product);
      // 付与は購入ストリーム側で自動処理される。
    } catch (e) {
      _toast('購入を開始できませんでした');
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(pointsProvider).valueOrNull ?? 0;
    final iap = ref.watch(iapServiceProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.ink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'ポイント',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Text(
                  '◆ $points',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'AI解析は1回 ${Monetization.analysisCost} ポイント。'
              '広告を見るか、まとめて購入して補充できます。',
              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 20),

            // 広告視聴
            FilledButton.icon(
              onPressed: _watchingAd ? null : _watchAd,
              icon: _watchingAd
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_circle_outline),
              label: Text(
                _watchingAd
                    ? '読み込み中…'
                    : '広告を見て +${Monetization.rewardPerAd} ポイント',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 16),

            // 課金（ポイントパック）
            Text(
              'まとめて購入',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (!iap.available)
              const Text(
                'ストアに接続できません（商品登録前・非対応端末の可能性）',
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              )
            else if (iap.products.isEmpty)
              const Text(
                '購入できる商品がありません。ストアで商品を登録してください。',
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              )
            else
              for (final product in iap.products) ...[
                _ProductTile(
                  product: product,
                  points: Monetization.productToPoints[product.id] ?? 0,
                  onTap: () => _buy(product),
                ),
                const SizedBox(height: 8),
              ],

            if (Monetization.usingTestAdIds) ...[
              const SizedBox(height: 12),
              Text(
                '※ 現在は広告テストIDです。リリース前に本番IDへ差し替えてください。',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.inkSoft.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final ProductDetails product;
  final int points;
  final VoidCallback onTap;

  const _ProductTile({
    required this.product,
    required this.points,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Text('◆', style: TextStyle(color: AppColors.accent)),
              const SizedBox(width: 8),
              Text(
                '$points ポイント',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                product.price,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
