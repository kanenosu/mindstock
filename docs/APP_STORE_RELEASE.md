# Mind Stock — App Store公開準備

更新日: 2026-09-24

## アプリ情報

- プラットフォーム: iOS / iPadOS
- Bundle ID: `com.kanenosu.mindstock`
- バージョン: `0.2.4`
- SKU案: `mindstock-ios-001`
- 主カテゴリ: ライフスタイル
- 副カテゴリ: 仕事効率化
- 価格: 無料（消費型アプリ内課金あり）
- プライバシーポリシー: `https://mindstock-zfwv.onrender.com/privacy`
- サポートURL: `https://mindstock-zfwv.onrender.com/support`

## 日本語メタデータ

- 名前: `Mind Stock`
- サブタイトル: `日記が人生チャートになる`
- キーワード: `日記,ジャーナル,気分,記録,習慣,振り返り,自己分析,ライフログ,AI,チャート`
- プロモーションテキスト:
  `書くだけで、毎日の出来事が人生のチャートに。AIが日記を整理し、変化や成長を振り返りやすくします。`
- 説明:

  `Mind Stockは、日記を「人生の値動き」として見える化するジャーナルアプリです。文章や気分を記録すると、AIが出来事を整理し、日々の変化をチャートへ反映します。`

  `主な機能`

  `・日記と気分をすばやく記録`

  `・音声入力から自動で文字起こし`

  `・日／週／月のチャートで変化を振り返り`

  `・昨日、1か月前、半年前、1年前の自分と比較`

  `・AIのまとめ方を好みに合わせて変更`

  `・日本語／英語、テーマカラーを設定`

  `・Googleドライブへの任意バックアップ`

  `日記データは基本的に端末内へ保存されます。AI解析や音声文字起こしを使う場合のみ、必要な内容が処理のために送信されます。`

## English metadata

- Name: `Mind Stock`
- Subtitle: `Your journal, visualized`
- Keywords: `journal,diary,mood,tracker,reflection,habits,life log,AI,chart,self growth`
- Promotional text:
  `Turn everyday journal entries into a visual life chart. AI organizes key moments so you can reflect on change and growth over time.`
- Description:

  `Mind Stock turns your journal into a visual chart of your life. Write about your day or record a mood, and AI organizes meaningful events into a timeline you can revisit.`

  `Key features`

  `• Quick journal and mood entries`

  `• Voice recording with automatic transcription`

  `• Daily, weekly, and monthly charts`

  `• Comparisons with your past self`

  `• Multiple AI summary styles`

  `• Japanese and English interface with selectable themes`

  `• Optional Google Drive backup`

  `Journal data is normally stored on your device. Content is transmitted only when needed for AI analysis or voice transcription.`

## スクリーンショット

最低1枚、最大10枚。現在はiPhoneとiPadの両方を対象にしているため、以下の2系統が必要。

- iPhone 6.9インチ: `1320 × 2868`、`1290 × 2796`、または `1260 × 2736`（縦）
- iPad 13インチ: `2064 × 2752` または `2048 × 2732`（縦）

推奨構成は5枚。

1. ホーム — 「毎日を、人生のチャートへ」
2. 日記入力 — 「書く・話す。記録はすぐ終わる」
3. 推移チャート — 「変化と成長を見える化」
4. 振り返り — 「過去の自分と比べられる」
5. 設定 — 「言語・色・AIのまとめ方を選べる」

## App Privacy回答の下書き

AdMobを含むため「データを収集しない」にはできない。最終回答はXcodeのPrivacy Reportと、その時点の各SDK公式開示を照合する。

- おおよその位置情報: 第三者広告、分析（IPアドレスから推定）
- デバイスID: 第三者広告、分析
- 広告データ: 第三者広告、分析
- 製品の操作: 第三者広告、分析
- クラッシュデータ: 分析、アプリ機能
- パフォーマンスデータ: 分析、第三者広告
- メールアドレス・名前: Googleバックアップを本人が有効化した場合のアプリ機能
- ユーザーコンテンツ（日記・音声）: AI解析／文字起こしのアプリ機能。サーバーでは保存しない
- 購入履歴: アプリ内課金の機能、不正防止

ATTを要求する実装は入れていない。広告はUMP同意取得後にのみ要求し、iOSが許可していないIDFAは送られない。将来、ATTを追加して追跡を行う場合は、実装・プライバシーポリシー・App Privacy回答を同時に更新する。

## アプリ内課金（消費型）

App Store Connectで次の商品IDを作り、初回アプリ版と一緒に審査へ提出する。

| 商品ID | 参照名 | 日本語表示名 | English display name |
|---|---|---|---|
| `points_10` | 10 Points | 10ポイント | 10 Points |
| `points_50` | 50 Points | 50ポイント | 50 Points |
| `points_150` | 150 Points | 150ポイント | 150 Points |

価格はApp Store Connectで決定する。各商品に審査用スクリーンショットを1枚添付する。

## App Reviewメモ案

`Mind Stock does not require an account. Seven points are granted on first launch, so the reviewer can test AI journal analysis without making a purchase or watching an ad. Google Sign-In is optional and is used only for backup to the user's private Google Drive app-data folder. Rewarded ads and consumable point packs are optional ways to obtain additional AI-analysis points. Voice recordings are sent for transcription only after the user holds the microphone button and grants microphone permission.`

## 残作業

- Apple Developer Programの有効な契約を確認
- App Store Connectでアプリレコードを作成
- Paid Apps Agreement、税務、銀行口座を完了（課金販売に必要）
- AdMobの「プライバシーとメッセージ」でEEA/UK向けメッセージを公開
- Codemagicに`app_store_credentials`と`app_runtime_secrets`を登録
- Xcode 26 / Codemagicで署名付きIPAを作成しTestFlightへ送信
- 実機で、音声・Googleバックアップ・広告・Sandbox課金を確認
- iPhone/iPadスクリーンショットを作成
- App Privacy、年齢区分、輸出コンプライアンス、IAPを入力
- TestFlight確認後、アプリ本体と3つのIAPを同じ審査へ提出
