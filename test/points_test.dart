import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindstock/config/monetization.dart';
import 'package:mindstock/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // 初期化を待つ
    await c.read(pointsProvider.future);
    return c;
  }

  test('初回は初期ポイントが付与される', () async {
    final c = await containerWith({});
    expect(c.read(pointsProvider).valueOrNull, Monetization.initialPoints);
  });

  test('spend で残高が減り、足りなければ false', () async {
    final c = await containerWith({'points_balance': 2});
    final notifier = c.read(pointsProvider.notifier);

    expect(await notifier.spend(1), isTrue);
    expect(c.read(pointsProvider).valueOrNull, 1);

    expect(await notifier.spend(5), isFalse); // 足りない
    expect(c.read(pointsProvider).valueOrNull, 1); // 変わらない
  });

  test('add で残高が増える', () async {
    final c = await containerWith({'points_balance': 0});
    await c.read(pointsProvider.notifier).add(Monetization.rewardPerAd);
    expect(c.read(pointsProvider).valueOrNull, Monetization.rewardPerAd);
  });

  test('残高は0未満にならない', () async {
    final c = await containerWith({'points_balance': 0});
    // spend は失敗するので残高は0のまま
    expect(await c.read(pointsProvider.notifier).spend(1), isFalse);
    expect(c.read(pointsProvider).valueOrNull, 0);
  });
}
