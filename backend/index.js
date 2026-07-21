// MindStock 解析バックエンド。
//
// 役割: 開発者のAIキー（OPENAI_API_KEY）をサーバー側に保持し、
// アプリからの「日記本文 → 出来事の採点」リクエストを代理実行する。
// これにより、アプリにキーを埋め込まずに開発者のキーで解析できる
// （キー流出を防ぐ）。収益は広告・課金でまかなう想定。
// AIはOpenAI（Chat Completions）のみを使用する。
//
// アプリは POST /analyze に {text, recent:[{date, summary}]} を送り、
// {events:[...]} を受け取る。
//
// デプロイ: Render / Railway / Fly.io / Cloud Run など Node が動く所ならどこでも。
//   1. このディレクトリで `npm install`
//   2. 環境変数 OPENAI_API_KEY を設定（音声入力(/transcribe)も同じキーを使う）
//   3. `npm start`（デフォルト3000番ポート）
//   4. 公開URLを、アプリのビルド時に --dart-define=BACKEND_URL=https://... で渡す
//
// ⚠️ 本番の注意: 以下の認証・レート制限は「誰でも無制限に叩ける」状態を
// 塞ぐための暫定策であり、Play Integrity / App Check のような
// 端末の正当性そのものを検証する仕組みではない（APP_SHARED_SECRETは
// アプリのビルド成果物を解析すれば抜き出せる）。本格的な不正対策には
// 別途 Play Integrity API / App Check の導入が必要。
//   - APP_SHARED_SECRET: アプリ・サーバー間の共有シークレット（下記参照）
//   - レート制限: IPごとに一定時間あたりのリクエスト数を制限
// 将来的にサーバー側でポイント残高を管理し、広告報酬・課金レシートを
// 検証してから解析する設計にする場合のフックは analyze ハンドラ内にコメントで示す。

import express from "express";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const app = express();
app.set("trust proxy", true); // Render等リバースプロキシ配下でreq.ipを正しく取るため
app.use(express.json({ limit: "256kb" }));

// Play Store / App Store のストア掲載情報に登録するプライバシーポリシー。
// 公開URL: {BACKEND_URL}/privacy
app.get("/privacy", (_req, res) => {
  res.sendFile(path.join(__dirname, "public", "privacy.html"));
});

// OpenAI APIキー。解析(/analyze)・音声入力(/transcribe)の両方で使う。
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
// 解析に使うOpenAIモデル（任意。既定は gpt-5.1）。
const MODEL = process.env.MODEL || "gpt-5.1";

// アプリ・サーバー間の共有シークレット。設定した場合、アプリ側は
// リクエストヘッダー `X-App-Secret` に同じ値を付けて送る必要がある。
// 未設定の場合はこのチェックをスキップする（後方互換・開発用）。
const APP_SHARED_SECRET = process.env.APP_SHARED_SECRET;

// ── 簡易レート制限（IPごと・インメモリ） ──────────────────────
// 複数インスタンスにスケールすると各インスタンスで別カウントになる点に
// 注意（MVPとしては許容。厳密にやるならRedis等の共有ストアが必要）。
const RATE_LIMIT_WINDOW_MS = 60_000; // 1分
const RATE_LIMIT_MAX = 20; // 1分あたり最大20リクエスト/IP
const rateLimitBuckets = new Map(); // ip -> {count, resetAt}

function rateLimit(req, res, next) {
  const ip = req.ip || "unknown";
  const now = Date.now();
  const bucket = rateLimitBuckets.get(ip);
  if (!bucket || now > bucket.resetAt) {
    rateLimitBuckets.set(ip, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return next();
  }
  if (bucket.count >= RATE_LIMIT_MAX) {
    const retryAfterSec = Math.ceil((bucket.resetAt - now) / 1000);
    res.set("Retry-After", String(retryAfterSec));
    return res.status(429).json({ error: "too many requests" });
  }
  bucket.count++;
  next();
}

// 定期的に古いバケットを掃除（メモリリーク防止）。
setInterval(() => {
  const now = Date.now();
  for (const [ip, bucket] of rateLimitBuckets) {
    if (now > bucket.resetAt) rateLimitBuckets.delete(ip);
  }
}, RATE_LIMIT_WINDOW_MS).unref();

function checkAppSecret(req, res, next) {
  if (!APP_SHARED_SECRET) return next(); // 未設定なら従来通り素通り
  const provided = req.get("X-App-Secret");
  if (provided !== APP_SHARED_SECRET) {
    return res.status(401).json({ error: "unauthorized" });
  }
  next();
}

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

app.post("/analyze", rateLimit, checkAppSecret, async (req, res) => {
  if (!OPENAI_API_KEY) {
    return res.status(500).json({ error: "OPENAI_API_KEY is not set" });
  }

  // === ここに本番のポイント検証を入れる ===
  // 例: ユーザーのポイント残高チェック、広告報酬/課金レシートの検証など。
  // 現状はアプリ側でポイントを管理しているため未実装（改ざん耐性は無い）。
  // 上の rateLimit / checkAppSecret は「誰でも無制限に叩ける」状態への
  // 暫定対策であり、本格的な不正対策にはPlay Integrity/App Checkが必要。

  const { text, recent } = req.body || {};
  if (typeof text !== "string" || text.trim() === "") {
    return res.json({ events: [] });
  }

  try {
    // OpenAI Structured Outputs（json_schema）で {events:[...]} を強制する。
    const r = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: MODEL,
        response_format: {
          type: "json_schema",
          json_schema: { name: "diary_events", schema: OUTPUT_SCHEMA, strict: true },
        },
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: buildUserMessage(text, recent) },
        ],
      }),
    });

    if (!r.ok) {
      const body = await r.text();
      console.error("OpenAI error", r.status, body);
      return res.status(502).json({ error: "upstream error" });
    }

    const data = await r.json();
    const content = data.choices?.[0]?.message?.content;
    // 安全上の理由で拒否された場合など、内容が空ならイベント無しとして扱う。
    if (data.choices?.[0]?.message?.refusal || !content) {
      return res.json({ events: [] });
    }

    // アプリ側は {events:[...]} をそのままパースするので、そのまま返す。
    const parsed = JSON.parse(content);
    return res.json({ events: parsed.events || [] });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: "internal error" });
  }
});

// 音声文字起こし（Whisper）の代理実行。
// アプリは録音ファイルのバイト列をそのまま body に入れて POST する
// （Content-Type: application/octet-stream）。OpenAIキーはサーバー側にのみ置く。
// multipart はここで組み立てて OpenAI に転送する（Node18+ の FormData/Blob を使用）。
app.post(
  "/transcribe",
  rateLimit,
  checkAppSecret,
  express.raw({ type: "*/*", limit: "25mb" }),
  async (req, res) => {
    if (!OPENAI_API_KEY) {
      return res.status(500).json({ error: "OPENAI_API_KEY is not set" });
    }
    const audio = req.body;
    if (!audio || !audio.length) {
      return res.status(400).json({ error: "empty audio" });
    }
    try {
      const form = new FormData();
      form.append(
        "file",
        new Blob([audio], { type: "audio/m4a" }),
        "voice.m4a"
      );
      form.append("model", "whisper-1");
      form.append("language", "ja");

      const r = await fetch("https://api.openai.com/v1/audio/transcriptions", {
        method: "POST",
        headers: { Authorization: `Bearer ${OPENAI_API_KEY}` },
        body: form,
      });
      if (!r.ok) {
        const body = await r.text();
        console.error("OpenAI transcribe error", r.status, body);
        return res.status(502).json({ error: "upstream error" });
      }
      const data = await r.json();
      return res.json({ text: (data.text || "").trim() });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: "internal error" });
    }
  }
);

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`mindstock-backend listening on :${port}`));
