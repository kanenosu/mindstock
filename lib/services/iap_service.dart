import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/monetization.dart';

/// アプリ内課金（消費型ポイントパック）を扱うサービス。
///
/// ストアで購入されると、対応するポイントを付与する。売上は開発者に入る。
/// 商品は Play Console / App Store Connect に [Monetization.productIds] と
/// 同じIDの「消費型アイテム」として登録するまで購入できない。
///
/// 注意: 本番では不正防止のためサーバー側でレシート検証すべき。ここでは
/// クライアントで付与する最小構成（backend/ の検証エンドポイントに繋ぐ余地あり）。
class IapService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// ストアから取得した購入可能な商品。
  List<ProductDetails> products = const [];

  /// ストアが利用可能か（未登録・非対応端末では false）。
  bool available = false;

  void Function(int points)? _onGrant;

  /// 初期化。購入ストリームを購読し、商品情報を取得する。
  /// [onGrant] は購入成立時にポイントを付与するコールバック。
  Future<void> init({required void Function(int points) onGrant}) async {
    _onGrant = onGrant;
    try {
      available = await _iap.isAvailable();
    } catch (_) {
      available = false;
    }
    if (!available) return;

    _sub = _iap.purchaseStream.listen(_onPurchaseUpdate, onError: (_) {});

    try {
      final resp = await _iap.queryProductDetails(Monetization.productIds);
      products = resp.productDetails
        ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    } catch (_) {
      products = const [];
    }
  }

  /// 商品を購入する（消費型）。
  Future<void> buy(ProductDetails product) async {
    await _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        final pts = Monetization.productToPoints[p.productID];
        if (pts != null) _onGrant?.call(pts);
      }
      // 消費型は completePurchase してはじめて再購入できる。
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
