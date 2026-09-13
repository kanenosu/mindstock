import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/monetization.dart';
import '../providers.dart';
import '../l10n.dart';
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
        _toast(
          context.i18n.tr(
            'points_earned',
            args: {'reward': Monetization.rewardPerAd.toString()},
          ),
        );
      } else {
        _toast(context.i18n.tr('ad_not_ready'));
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
      _toast(context.i18n.tr('purchase_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(pointsProvider).valueOrNull ?? 0;
    final iap = ref.watch(iapServiceProvider);
    final i18n = context.i18n;

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
                  i18n.tr('points_sheet_title'),
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
              i18n.tr(
                'points_description',
                args: {'cost': Monetization.analysisCost.toString()},
              ),
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
                    ? i18n.tr('watch_ad_loading')
                    : i18n.tr(
                        'watch_ad_button',
                        args: {'reward': Monetization.rewardPerAd.toString()},
                      ),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 16),

            // 課金（ポイントパック）
            Text(
              i18n.tr('buy_pack_title'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (!iap.available)
              Text(
                i18n.tr('buy_empty_store'),
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              )
            else if (iap.products.isEmpty)
              Text(
                i18n.tr('buy_empty_product'),
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
                i18n.tr('ad_test_notice'),
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
              Row(
                children: [
                  Text('$points', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 2),
                  Text(
                    context.i18n.tr('points_chip'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
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
