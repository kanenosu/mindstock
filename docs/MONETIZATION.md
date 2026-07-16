# マネタイズ（ポイント制・広告・課金）の仕組みとリリース手順

## 全体像

AI解析は**ポイント**を消費して行う。ポイントは広告視聴・課金で補充する。
広告・課金の収益は開発者に入る。AIのコストは開発者のキーで支払い、
そのキーは**バックエンド（サーバー）に置く**（アプリには埋め込まない）。

```
アプリ ──(日記本文)──▶ バックエンド ──(開発者のキー)──▶ Claude
      ◀──(採点結果)──          ◀──(採点結果)──
  ▲
  └ ポイントが1以上ある時だけ解析できる。
    ポイント補充 = 広告を見る(+1) / ポイントを買う(課金)
```

- 初回付与: **3ポイント**（`Monetization.initialPoints`）
- AI解析1回: **1ポイント消費**（`Monetization.analysisCost`）
- 広告1本: **+1ポイント**（`Monetization.rewardPerAd`）
- 気分の絵文字だけの記録は無料（AIを叩かないため）

設定は `lib/config/monetization.dart` に集約。金額感を変えたい時はここを編集。

## なぜアプリにキーを埋め込まないのか

アプリ（APK/IPA）は誰でも解析してAPIキーを抜き出せる。埋め込むと
第三者があなたのキーで無制限にAIを叩き、**あなたに莫大な請求**が来る。
そのため、キーはサーバー側（`backend/`）に置き、アプリはサーバー経由で解析する。

## バックエンドのデプロイ

`backend/` に最小構成のNode.jsサーバーがある。

1. Node が動くホスティングを用意（Render / Railway / Fly.io / Cloud Run 等、無料枠可）
2. `backend/` を配置し、環境変数 `ANTHROPIC_API_KEY` を設定
3. 起動（`npm install && npm start`）
4. 公開URL（例 `https://mindstock.onrender.com`）を控える
5. アプリをそのURL付きでビルド:
   ```
   flutter build appbundle --release --dart-define=BACKEND_URL=https://mindstock.onrender.com
   ```
   （開発中は設定画面から一時的に差し替えることも可能）

> ⚠️ 現状の `backend/index.js` は認証なしで誰でも叩ける。本番前に必ず、
> アプリ認証（Play Integrity / App Check / DeviceCheck）の検証、ポイント残高の
> サーバー管理、広告報酬・課金レシートの検証、レート制限を足すこと。
> フックを入れる場所は `analyze` ハンドラ内にコメントで示してある。

## 広告（AdMob）

- 実装: `lib/services/rewarded_ad_service.dart`（リワード広告）
- 現在のID（`lib/config/monetization.dart`・AndroidManifest・Info.plist）は
  **Google公式のテストID**。審査前でも安全に動作確認できる。
- リリース前の手順:
  1. https://apps.admob.com でアプリを登録し、**アプリID**と
     **リワード広告ユニットID**を取得
  2. 次の3か所を本番IDに差し替える:
     - `lib/config/monetization.dart`（`admobAppId` / `rewardedAdUnitId`）
     - `android/app/src/main/AndroidManifest.xml`（`com.google.android.gms.ads.APPLICATION_ID`）
     - `ios/Runner/Info.plist`（`GADApplicationIdentifier`）
  3. iOS は `SKAdNetworkItems` にAdMob推奨のIDを追記（計測精度向上）
  4. app-ads.txt の設定（任意だが推奨）

## 課金（IAP: ポイントパック）

- 実装: `lib/services/iap_service.dart`（消費型アイテム）
- 商品IDは `lib/config/monetization.dart` の `productToPoints`
  （`points_10` / `points_50` / `points_150`）。付与ポイントもここで対応づけ。
- リリース前の手順:
  1. **Google Play Console**: アプリ内アイテム →「管理対象アイテム/消費型」で
     同じ商品IDを登録
  2. **App Store Connect**（Appleデベロッパー登録後）: App内課金 →「消費型」で
     同じ商品IDを登録
  3. 登録するまで購入UIは「購入できる商品がありません」と表示される（コードは動く）
  4. 本番では課金レシートをサーバーで検証してからポイント付与するのが望ましい

## リリース前チェックリスト

- [ ] バックエンドをデプロイし `BACKEND_URL` を dart-define で焼き込んだ
- [ ] バックエンドに認証・ポイント検証・レート制限を実装した
- [ ] AdMob 本番ID（3か所）に差し替えた
- [ ] IAP 商品を各ストアに登録した
- [ ] Android: リリース署名（`android/app/build.gradle.kts` の signingConfig）
- [ ] iOS: Appleデベロッパー登録 → 証明書・プロビジョニング（未登録なら保留）
- [ ] プライバシーポリシー（広告・課金があるため各ストアで必須）

## Apple について

現状 Apple デベロッパー登録が未完のため、iOS の IAP 商品登録・実機課金テスト・
ストア申請はできない。コードは iOS でもビルドできる状態にしてあるので、
登録が済み次第、上記の IAP 商品登録と AdMob iOS 本番ID設定を行えばよい。
それまでは Android（Google Play）を先行リリースする形で進められる。
