// MindStock 解析バックエンド。
//
// 役割: 開発者のAIキー（ANTHROPIC_API_KEY）をサーバー側に保持し、
// アプリからの「日記本文 → 出来事の採点」リクエストを代理実行する。
// これにより、アプリにキーを埋め込まずに開発者のキーで解析できる
// （キー流出を防ぐ）。収益は広告・課金でまかなう想定。
//
// アプリは POST /analyze に {text, recent:[{date, summary}]} を送り、
// {events:[...]} を受け取る。
//
// デプロイ: Render / Railway / Fly.io / Cloud Run など Node が動く所ならどこでも。
//   1. このディレクトリで `npm install`
//   2. 環境変数 ANTHROPIC_API_KEY を設定
//   3. `npm start`（デフォルト3000番ポート）
//   4. 公開URLを、アプリのビルド時に --dart-define=BACKEND_URL=https://... で渡す
//
// ⚠️ 本番の注意: このままだと誰でも /analyze を叩けて、あなたのAIキーで
// 課金が発生し得る。実運用では最低限、以下を足すこと:
//   - アプリ側の認証（App Check / Play Integrity / DeviceCheck など）を検証
//   - サーバー側でポイント残高を管理し、広告報酬・課金レシートを検証してから解析
//   - レート制限
// （今はMVP。上記フックを入れる場所は analyze ハンドラ内にコメントで示す）

import express from "express";

const app = express();
app.use(express.json({ limit: "256kb" }));

const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
const MODEL = process.env.MODEL || "claude-haiku-4-5";

// アプリ側 (lib/services/diary_analyzer.dart) の kAnalyzerSystemPrompt と同じ内容。
// 変更する時は両方を揃えること。
const SYSTEM_PROMPT = `あなたは日記アプリの解析エンジンです。日記本文から「実際に起きた出来事」を最大4件抽出し、
人生チャートの株価変動値を計算してください。

【最優先ルール：抽出してはいけないもの】
以下は「まだ起きていないこと」なので、絶対に出来事として抽出しない（採点もしない）:
- 未来の目標・決意・意気込み（例:「これから毎日走る」「強い男になる」「絶対に合格する」「痩せたい」「変わろうと思う」「頑張る」）
- 願望・仮定・たとえ話（例:「〜だったらいいな」「もし〜なら」）
判定のコツ: 文末が「〜たい / 〜しよう / 〜するつもり / 〜になる / 〜がんばる」のような
未来・意志の形なら、それは決意であって出来事ではない。
実際に「やった」「起きた」「言われた」など、過去・完了の事実だけを出来事として扱う。
その文に実際の行動・結果が伴っていなければ採点しない。決意しか書かれていない日は
events を空配列 [] にする。

【例】
- 「今日はジムに行った。これから毎日通って絶対に痩せる！」
  → 抽出するのは「ジムに行った」だけ。「絶対に痩せる」は決意なので無視。
- 「強い男になると決めた。」→ 実際の行動がまだ無いので events は [] にする。

株価変動値は次の式で求めます。
change = 方向 × baseImportance × durationMultiplier × moodMultiplier × 1.5
ポジティブはプラス、ネガティブはマイナス。最終値は四捨五入します。

baseImportance（1〜100）: 出来事そのものの客観的重要度です。感情の強さとは分けて判断してください。
- 小さな日常: 1〜5
- 普通の日常: 6〜15
- 重要な出来事: 16〜40
- 人生の節目: 41〜75
- 健康・生命・人生全体への重大な影響: 76〜100
基礎重要度には、生活への影響範囲と元に戻りにくさを含めます。

durationMultiplier:
- 数時間: 0.5
- 1日: 0.7
- 数日: 0.9
- 数週間: 1.1
- 数か月: 1.3
- 数年以上: 1.5

moodMultiplier: 本文に明示された感情の強さだけを使います。
- ほぼ感情なし: 0.8
- 弱い: 0.9
- 普通: 1.0
- 強い: 1.15
- 非常に強い: 1.3
感情が強くても、日常的で短期的な出来事を大きく採点してはいけません。

kind:
- daily: 日常的・一時的な出来事
- mood: 具体的な原因のない気分変化
- milestone: 進路、人間関係、健康、所属などが長期的に変わる節目

dailyのchangeは原則±10以内、1日のdaily合計は±15以内にしてください。
同じ原因の出来事と感情は重複抽出しません。似た出来事が直近の日記で繰り返されている場合は、
baseImportanceを下げます。判断材料が少ない場合は控えめに採点してください。

出力ルール:
- name は日本語で15文字以内の短い名詞句。
- 出来事が読み取れない場合は空の配列を返す。
- JSON以外は出力しないでください。`;

const OUTPUT_SCHEMA = {
  type: "object",
  properties: {
    events: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          kind: { type: "string", enum: ["daily", "mood", "milestone"] },
          isPositive: { type: "boolean" },
          baseImportance: { type: "number" },
          durationMultiplier: { type: "number" },
          moodMultiplier: { type: "number" },
          change: { type: "number" },
        },
        required: [
          "name",
          "kind",
          "isPositive",
          "baseImportance",
          "durationMultiplier",
          "moodMultiplier",
          "change",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["events"],
  additionalProperties: false,
};

function buildUserMessage(text, recent) {
  const lines = (recent || [])
    .slice(0, 7)
    .map((r) => `- ${r.date}: ${r.summary}`)
    .join("\n");
  return (
    "直近の日記（快楽順応の判定に使うこと）:\n" +
    (lines || "（なし）") +
    "\n\n今日の日記本文:\n" +
    (text || "")
  );
}

app.get("/health", (_req, res) => res.json({ ok: true }));

app.post("/analyze", async (req, res) => {
  if (!ANTHROPIC_API_KEY) {
    return res.status(500).json({ error: "ANTHROPIC_API_KEY is not set" });
  }

  // === ここに本番の認証・ポイント検証・レート制限を入れる ===
  // 例: App Check トークンの検証、ユーザーのポイント残高チェック、
  //     広告報酬/課金レシートの検証など。未実装だと誰でも叩けるので注意。

  const { text, recent } = req.body || {};
  if (typeof text !== "string" || text.trim() === "") {
    return res.json({ events: [] });
  }

  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 2048,
        system: SYSTEM_PROMPT,
        output_config: { format: { type: "json_schema", schema: OUTPUT_SCHEMA } },
        messages: [{ role: "user", content: buildUserMessage(text, recent) }],
      }),
    });

    if (!r.ok) {
      const body = await r.text();
      console.error("Anthropic error", r.status, body);
      return res.status(502).json({ error: "upstream error" });
    }

    const data = await r.json();
    if (data.stop_reason === "refusal") {
      return res.json({ events: [] });
    }
    const textBlock = (data.content || []).find((b) => b.type === "text");
    if (!textBlock) return res.json({ events: [] });

    // アプリ側は {events:[...]} をそのままパースするので、そのまま返す。
    const parsed = JSON.parse(textBlock.text);
    return res.json({ events: parsed.events || [] });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: "internal error" });
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`mindstock-backend listening on :${port}`));
