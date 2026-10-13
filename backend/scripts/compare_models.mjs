// /analyze の精度比較スクリプト。同じプロンプト・スキーマで複数モデルを回して並べて表示する。
//
// 使い方（backend/ で）:
//   OPENAI_API_KEY=sk-... node scripts/compare_models.mjs
//   OPENAI_API_KEY=sk-... node scripts/compare_models.mjs gpt-5.1 gpt-6-luna gpt-6-sol
//
// プロンプトとスキーマは index.js から読み取るので、二重管理にならない。

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");

const SYSTEM_PROMPT = new Function(
  `return ${src.match(/const SYSTEM_PROMPT = (`[\s\S]*?`);/)[1]}`,
)();
const OUTPUT_SCHEMA = new Function(
  `return ${src.match(/const OUTPUT_SCHEMA = (\{[\s\S]*?\n\});/)[1]}`,
)();

const KEY = process.env.OPENAI_API_KEY;
if (!KEY) {
  console.error("OPENAI_API_KEY を環境変数で渡して");
  process.exit(1);
}
const MODELS = process.argv.slice(2).length ? process.argv.slice(2) : ["gpt-5.1", "gpt-6-luna"];

// expect: 期待する挙動のメモ（自動判定ではなく目視用）
const CASES = [
  { name: "決意だけ（events=[]が正解）", text: "強い男になると決めた。", expect: "events は []" },
  {
    name: "行動+決意（ジムだけ拾う）",
    text: "今日はジムに行った。これから毎日通って絶対に痩せる！",
    expect: "「ジムに行った」だけ。痩せるは無視",
  },
  {
    name: "普通の日常",
    text: "友達とラーメンを食べに行った。美味しくてかなり満足だった。",
    expect: "daily、±10以内",
  },
  {
    name: "人生の節目",
    text: "第一志望の会社から内定をもらった。嬉しすぎて泣いた。",
    expect: "milestone、大きめのプラス",
  },
  {
    name: "ネガティブ+気分",
    text: "バイトで大きなミスをして店長に怒られた。一日中落ち込んでいる。",
    expect: "マイナス。出来事と気分を二重計上しない",
  },
  {
    name: "快楽順応（直近で繰り返し）",
    text: "今日もラーメンを食べに行った。美味しかった。",
    recent: [
      { date: "2026-10-12", summary: "ラーメンを食べた" },
      { date: "2026-10-11", summary: "ラーメンを食べた" },
      { date: "2026-10-10", summary: "ラーメンを食べた" },
    ],
    expect: "baseImportance を下げて小さめ",
  },
  { name: "出来事なし", text: "特になし。", expect: "events は []" },
];

function userMessage(text, recent) {
  const lines = (recent || []).map((r) => `- ${r.date}: ${r.summary}`).join("\n");
  return `直近の日記（快楽順応の判定に使うこと）:\n${lines || "（なし）"}\n\n今日の日記本文:\n${text}`;
}

async function call(model, c) {
  const t0 = Date.now();
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${KEY}` },
    body: JSON.stringify({
      model,
      response_format: {
        type: "json_schema",
        json_schema: { name: "diary_events", schema: OUTPUT_SCHEMA, strict: true },
      },
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userMessage(c.text, c.recent) },
      ],
    }),
  });
  const ms = Date.now() - t0;
  if (!r.ok) return { error: `HTTP ${r.status}: ${(await r.text()).slice(0, 300)}`, ms };
  const data = await r.json();
  const msg = data.choices?.[0]?.message;
  if (msg?.refusal || !msg?.content) return { error: `refusal/empty: ${msg?.refusal ?? ""}`, ms };
  try {
    return { events: JSON.parse(msg.content).events ?? [], ms, usage: data.usage };
  } catch (e) {
    return { error: `JSON parse失敗: ${e.message}`, ms };
  }
}

// 機械的に確認できる不整合だけ列挙する。
function lint(events) {
  const w = [];
  let dailySum = 0;
  for (const e of events) {
    const sign = e.isPositive ? 1 : -1;
    const calc = Math.round(sign * e.baseImportance * e.durationMultiplier * e.moodMultiplier * 1.5);
    if (Math.abs(calc - e.change) > 1) w.push(`式と不一致「${e.name}」: change=${e.change} 計算=${calc}`);
    if (e.name.length > 15) w.push(`name15文字超「${e.name}」`);
    if (e.kind === "daily") {
      dailySum += e.change;
      if (Math.abs(e.change) > 10) w.push(`daily が±10超「${e.name}」: ${e.change}`);
    }
    if (e.isPositive !== e.change > 0 && e.change !== 0) w.push(`符号がisPositiveと逆「${e.name}」`);
  }
  if (Math.abs(dailySum) > 15) w.push(`daily合計が±15超: ${dailySum}`);
  if (events.length > 4) w.push(`4件超: ${events.length}件`);
  return w;
}

for (const c of CASES) {
  console.log(`\n━━ ${c.name}\n  本文: ${c.text}\n  期待: ${c.expect}`);
  for (const model of MODELS) {
    const res = await call(model, c);
    if (res.error) {
      console.log(`  [${model}] ❌ ${res.error} (${res.ms}ms)`);
      continue;
    }
    const tok = res.usage ? ` in=${res.usage.prompt_tokens} out=${res.usage.completion_tokens}` : "";
    console.log(`  [${model}] ${res.events.length}件 (${res.ms}ms${tok})`);
    for (const e of res.events) {
      console.log(
        `     - ${e.name} | ${e.kind} | base=${e.baseImportance} dur=${e.durationMultiplier} mood=${e.moodMultiplier} → change=${e.change}`,
      );
    }
    for (const x of lint(res.events)) console.log(`     ⚠️ ${x}`);
  }
}
