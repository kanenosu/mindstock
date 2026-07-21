# マネタイズ（ポイント制・広告・課金）の仕組みとリリース手順

## 全体像

AI解析は**ポイント**を消費して行う。ポイントは広告視聴・課金で補充する。
広告・課金の収益は開発者に入る。AIのコストは開発者のキーで支払い、
そのキーは**バックエンド（サーバー）に置く**（アプリには埋め込まない）。

```
アプリ ──(日記本文)──▶ バックエンド ──(開発者のキー)──▶ OpenAI
      ◀──(採点結果)──          ◀──(採点結果)──
  ▲
  └ ポイントが1以上ある時だけ解析できる。
    ポイント補充 = 広告を見る(+1) / ポイントを買う(課金)
```

- 初回付与: **7ポイント**（`Monetization.initialPoints`）
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
2. `backend/` を配置し、環境変数 `OPENAI_API_KEY` を設定
   （解析(/analyze)と音声入力(/transcribe)の両方で同じOpenAIキーを使う）
3. 起動（`npm install && npm start`）
4. 公開URL（例 `https://mindstock.onrender.com`）を控える
5. アプリをそのURL付きでビルド:
   ```
   flutter build appbundle --release --dart-define=BACKEND_URL=https://mindstock.onrender.com
   ```
   （開発中は設定画面から一時的に差し替えることも可能）

### デプロイ済み（Render）

- サービス名: `mindstock-backend`（Render Free プラン、GitHub連携: `kanenosu/mindstock`、Root Directory: `backend`）
- 公開URL: `https://mindstock-backend.onrender.com`
- `/health` で疎通確認済み（2026-07-17）
- Free プランは無通信が続くとスピンダウンし、次のリクエストで起動まで50秒程度かかる点に注意
- ビルド時は `--dart-define=BACKEND_URL=https://mindstock-backend.onrender.com` を渡す

> ⚠️ `backend/index.js` には現在、IPごとのレート制限（1分20回）と
> アプリ・サーバー間の共有シークレット（`APP_SHARED_SECRET` / ヘッダー
> `X-App-Secret`）による簡易認証を実装済み。ただし共有シークレットは
> APKを解析すれば抜き出せるため、Play Integrity / App Check のような
> 端末の正当性検証の代替にはならない（暫定策）。本番運用では、
> ポイント残高のサーバー管理・広告報酬/課金レシートの検証・
> Play Integrity/App Checkの導入を追加で検討すること。
> フックを入れる場所は `analyze` ハンドラ内にコメントで示してある。
>
> `APP_SHARED_SECRET` を使う場合、アプリのビルド時に同じ値を
> `--dart-define=APP_SHARED_SECRET=...` で渡す必要がある
> （`backend/.env.example` 参照）。

## 広告（AdMob）

- 実装: `lib/services/rewarded_ad_service.dart`（リワード広告）
- 本番ID設定済み（2026-07-17、apps.admob.com の「MindStock」アプリ、
  Android/iOS両方、リワード広告ユニット名 `Rewarded_Diary_Point`）:
  - `lib/config/monetization.dart`（`admobAppId` / `rewardedAdUnitId`）
  - `android/app/src/main/AndroidManifest.xml`（`com.google.android.gms.ads.APPLICATION_ID`）
  - `ios/Runner/Info.plist`（`GADApplicationIdentifier`）
- ⚠️ AdMobアカウントの**お支払いプロファイルが未設定**。追加するまで
  アプリの審査が開始されない（＝広告配信も始まらない）。AdMobの
  「お支払い」から設定すること（銀行口座情報の入力が必要）。
- 残りの手順:
  1. iOS は `SKAdNetworkItems` にAdMob推奨のIDを追記（計測精度向上、未対応）
  2. app-ads.txt の設定（任意だが推奨、未対応）

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

- [x] バックエンドをデプロイし `BACKEND_URL` を dart-define で焼き込んだ（`https://mindstock-backend.onrender.com`、要: 実際のリリースビルド時に dart-define を渡すこと）
- [x] バックエンドにレート制限（IP毎1分20回）と共有シークレット認証（`APP_SHARED_SECRET`）を実装した（暫定策。Play Integrity/App Check・ポイント残高のサーバー管理・課金レシート検証は未実装）
- [x] AdMob 本番ID（3か所）に差し替えた（2026-07-17。ただし支払いプロファイル未設定でアプリ審査は未開始）
- [ ] IAP 商品を各ストアに登録した
- [ ] Android: リリース署名。`android/app/build.gradle.kts` は `android/key.properties`
      （`key.properties.example` を参考に作成。gitignore済み・非公開）があれば自動でそれを使う。
      無ければdebug鍵にフォールバックし、Play Storeが「デバッグモードで署名されています」と
      エラーを出す。キーストアの作り方は `keytool -genkey -v -keystore <path>.jks
      -keyalg RSA -keysize 2048 -validity 10000 -alias mindstock`
      （キーストアは紛失・流出させないこと。紛失すると同じ署名でのアップデート配信ができなくなる）
- [ ] iOS: Appleデベロッパー登録 → 証明書・プロビジョニング（未登録なら保留）
- [x] プライバシーポリシー（`backend/public/privacy.html`、公開URL: `{BACKEND_URL}/privacy`
      例: `https://mindstock-backend.onrender.com/privacy`。Play Console →
      アプリのコンテンツ → プライバシーポリシー にこのURLを登録する）

## Apple について

現状 Apple デベロッパー登録が未完のため、iOS の IAP 商品登録・実機課金テスト・
ストア申請はできない。コードは iOS でもビルドできる状態にしてあるので、
登録が済み次第、上記の IAP 商品登録と AdMob iOS 本番ID設定を行えばよい。
それまでは Android（Google Play）を先行リリースする形で進められる。
