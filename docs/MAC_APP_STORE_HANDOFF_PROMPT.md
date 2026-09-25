# Mind Stock — MacでApp Store公開を完了するためのプロンプト

以下を、Mac上でこのリポジトリを開いたCodexへそのまま渡してください。

---

Mind StockのiOS版を、TestFlightへのアップロードとApp Store審査提出直前まで完成させてください。安全確認、ビルド、実機またはSimulatorテスト、スクリーンショット作成、App Store Connect設定を順番に進め、各段階で結果を検証してください。

## 重要な前提

- GitHub: `https://github.com/kanenosu/mindstock.git`
- ブランチ: `claude/life-chart-diary-spec-na0uu0`
- Bundle ID: `com.kanenosu.mindstock`
- Apple Team ID: `9U66V9DMAW`
- App Store Connect App ID: `6816151496`
- 現在のアプリ版: `0.2.4+6`
- バックエンド: `https://mindstock-zfwv.onrender.com`
- プライバシーポリシー: `https://mindstock-zfwv.onrender.com/privacy`
- サポート: `https://mindstock-zfwv.onrender.com/support`
- App Store Connectにはアプリレコード作成済み。初期表示のバージョンは`1.0`なので、ビルドと合わせて`0.2.4`へ変更する。
- iOSの最終署名・IPA作成はまだ実施していない。
- Windows側では`flutter analyze`と全60テストが合格済み。
- Git履歴はAndroid署名情報を除去するため書き換え済み。Macに古いcloneがある場合はpullせず、別フォルダへ再cloneすること。

## 絶対に守ること

- `APP_SHARED_SECRET`、Appleの秘密鍵、証明書、パスワードをGitへ追加しない。画面やログにも表示しない。
- 秘密値が必要なら、ユーザー自身にMacの環境変数または安全なSecretストアへ入力してもらう。
- App Storeの審査提出ボタン、法的契約への同意、DSA区分、税務・銀行情報、APIキー作成、課金価格の確定は、実行直前に内容を説明してユーザーの確認を取る。
- Androidの古い署名鍵は漏洩扱い。再利用しない。
- 既存の実装を勝手に消さず、問題があれば原因を修正して再検証する。

## 1. 新しいcloneとMac環境確認

1. リポジトリを新しいフォルダへcloneし、指定ブランチをcheckoutする。
2. Xcode 26.6以降、Flutter stable、CocoaPodsが利用できることを確認する。
3. `flutter doctor -v`、`flutter pub get`、`flutter analyze`、`flutter test`を実行する。
4. `ios/Podfile`を使って`pod install`し、`ios/Runner.xcworkspace`を開く。
5. RunnerターゲットでTeam `9U66V9DMAW`、Bundle ID `com.kanenosu.mindstock`、Automatically manage signingを設定する。

## 2. iOS動作確認

`BACKEND_URL`は上記URL、`APP_SHARED_SECRET`はユーザーの安全な環境変数から渡す。最低限、次をiPhone Simulatorで確認する。

- 初回起動と言語選択（日本語／英語）
- 日記保存、AI解析失敗時のフォールバック、チャート表示
- 設定から言語・テーマカラー・AIまとめ方を変更
- マイク許可と音声文字起こし
- Googleログインが任意であること。失敗する場合はiOS OAuth設定とURL Schemeを確認
- Google Driveバックアップ
- UMP広告同意、リワード広告
- StoreKit Sandboxで消費型課金を確認
- アカウントなしで利用でき、初回7ポイントが付与されること
- iPhoneとiPadの両方でレイアウト崩れがないこと

不具合を修正したら、再度`flutter analyze`と`flutter test`を通す。

## 3. App Store用スクリーンショット

個人情報を含まないサンプル日記をSimulator内だけに作成し、日本語版と英語版を用意する。App Store Connectが現在要求している正確なピクセル寸法を画面で再確認し、少なくとも次の5画面をiPhone用に作成する。iPadが必須表示ならiPad版も作成する。

1. 人生チャートが見えるホーム
2. 日記入力と音声入力
3. 日／週／月のチャート
4. 過去記録・振り返り
5. 言語・テーマ・AIまとめ方の設定

デバッグバナー、開発用URL、個人情報、ダミーエラーを写さない。画像の内容とアプリの実画面を一致させる。

## 4. ArchiveとTestFlight

1. `pubspec.yaml`の`0.2.4+6`とApp Store Connectの`0.2.4`が一致することを確認する。
2. 本番の`BACKEND_URL`と`APP_SHARED_SECRET`をdart-defineで渡してRelease IPAを作る。
3. Xcode OrganizerまたはTransporterからApp Store Connectへアップロードする。
4. ビルド処理完了後、TestFlightの内部テストへ追加する。
5. TestFlightで起動・課金・広告・音声・Googleログインを再確認する。

Macで直接Xcodeを使えるため、Codemagicは必須ではない。ローカル署名で解決できない場合のみ`codemagic.yaml`を使う。

## 5. App Store Connectの公開情報

`docs/APP_STORE_RELEASE.md`を正本として日本語・英語の説明、プロモーション文、キーワードを入力する。

- サブタイトル: `日記が人生チャートになる`
- Primary category: Lifestyle
- Secondary category: Productivity
- サポートURL: `https://mindstock-zfwv.onrender.com/support`
- プライバシーURL: `https://mindstock-zfwv.onrender.com/privacy`
- サインイン必須: オフ
- 初回リリース方法: ユーザーに確認。迷う場合は手動リリースを提案
- 年齢制限: 広告あり。その他は実装を確認して正確に回答
- App Privacy: AdMob、任意のGoogleログイン／Drive、日記本文のAI解析、音声文字起こし、購入情報を実装に沿って申告

審査メモには以下を入力する。

`Mind Stock does not require an account. Seven points are granted on first launch, so the reviewer can test AI journal analysis without making a purchase or watching an ad. Google Sign-In is optional and is used only for backup to the user's private Google Drive app-data folder. Rewarded ads and consumable point packs are optional ways to obtain additional AI-analysis points. Voice recordings are sent for transcription only after the user holds the microphone button and grants microphone permission.`

## 6. 課金・契約・規制

- 消費型IAP: `points_10`、`points_50`、`points_150`
- 価格はユーザーに確認してから設定する。
- 有料アプリ契約は未同意。契約、税務、銀行情報はユーザー本人と一緒に設定する。
- EUのDSAトレーダー区分は未決定。法的意味を説明し、ユーザーに選択してもらう。
- 連絡先情報をApp Reviewへ入力する前に、氏名・電話番号・メールをAppleへ送信することを説明して確認する。

## 7. 完了条件

- iPhone／iPadで主要機能の動作確認済み
- Release IPAがApp Store Connectで処理済み
- TestFlightで確認済み
- スクリーンショット、説明、カテゴリ、年齢制限、App Privacy、審査情報が保存済み
- IAPと契約が有効
- App Store Connect上の警告と未入力必須項目がゼロ

最後の「審査用に追加」「審査へ提出」は、実行直前に不足項目と送信内容を一覧化し、ユーザーから明示的な許可を得てから押してください。

---
