# ライフチャート 15秒広告動画 — 素材クレジット

いずれも 1080×1920 / 9:16 縦 / 60fps / 15秒 / H.264 + AAC。
HTML/CSS/SVG/Canvas で画面を組み、Playwright(Chromium) で1フレームずつ描画 → ffmpeg でエンコード。

| ファイル | 内容 |
|---|---|
| `lifechart_ad_15s_story.mp4` | **本命。** 紙の切り絵キャラのストーリー版。落ち込む → 日記を書く → 赤いローソク足 → カメラが引いて「半年前の自分（谷にいる）よりずっと上」に気づく → ジャンプ → ロゴ。キャラは12fpsのストップモーション風、カメラは60fpsで滑らか |
| `lifechart_ad_15s.mp4` | UI中心のプロダクト版（旧）。日記入力 → AI採点 → ダッシュボード → 推移チャート → ロゴ |

## 音声
- 効果音: [UI SFX (uisfx)](https://uisfx.com) — CC0 1.0（パブリックドメイン）。soft / zen / dreamy / organic パックを使用
- BGM: オリジナル作曲（MIDI）を FluidSynth + FluidR3_GM サウンドフォント（MIT License）でレンダリング。ストーリー版は Am→Fmaj7 の短調で始まり、カメラが引く5秒で C に開けて、12.5秒のロゴで解決する構成

## フォント
- Noto Sans JP / Inter / Noto Color Emoji（SIL OFL）、Material Symbols Rounded（Apache 2.0）

## 注意
- キャラクター・紙テクスチャ・チャートはすべて自作（SVG/生成画像）。外部イラスト素材は不使用。
- App Store / Google Play のバッジは公式素材ではなく、テキスト＋汎用アイコンの代用。公開時は各ストアの公式バッジに差し替えること。
