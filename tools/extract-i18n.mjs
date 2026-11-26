// i18n 字典程式化抽取：母本 ~/workspace/tuner-metronome/index.html
// → AcousticReference/Resources/localization.json
//
// 方法：以字串定位切出母本的 I18N 字面量與 I18N_PREFIXES 宣告，
// 在 Node vm 內求值取得原始數據物件（不手工謄抄任何一條）；
// tools/i18n-supplement.json（原生專屬字串，母本字典沒有者）
// 合併為獨立的 supplement 段，與母本字典分開標明出處。
// 核對：另以 JSON.parse 第二路徑獨立解析同一字面量，與求值
// 結果逐語逐鍵深比對；統計逐語鍵數與鍵集差異（缺鍵回退源串
// 為母本 translateString 的既定行為）；對照組 spot-check 已知
// 鍵。摘要寫入 tools/i18n-extraction-report.txt。
import { readFileSync, writeFileSync } from "node:fs";
import { createContext, runInContext } from "node:vm";

const home = process.env.HOME;
const htmlPath = home + "/workspace/tuner-metronome/index.html";
const supplementPath = home + "/workspace/laurent-acoustic-reference-ios/tools/i18n-supplement.json";
const outPath = home + "/workspace/laurent-acoustic-reference-ios/AcousticReference/Resources/localization.json";
const reportPath = home + "/workspace/laurent-acoustic-reference-ios/tools/i18n-extraction-report.txt";

const html = readFileSync(htmlPath, "utf8");

// --- 1. 切出 I18N 字面量並以 vm 求值 --------------------------------------
const i18nStart = html.indexOf("const I18N = ");
if (i18nStart < 0) throw new Error("I18N not found");
const braceStart = html.indexOf("{", i18nStart);
let depth = 0, i18nEnd = -1;
for (let i = braceStart; i < html.length; i++) {
  if (html[i] === "{") depth++;
  else if (html[i] === "}") { depth--; if (depth === 0) { i18nEnd = i + 1; break; } }
}
if (i18nEnd < 0) throw new Error("I18N literal not terminated");
const i18nLiteral = html.slice(braceStart, i18nEnd);

const ctx = createContext({});
runInContext("this.__I18N = " + i18nLiteral + ";", ctx);
const I18N = ctx.__I18N;

// I18N_PREFIXES：母本行 8127 的單行陣列字面量。
const prefixStart = html.indexOf("const I18N_PREFIXES = ");
if (prefixStart < 0) throw new Error("I18N_PREFIXES not found");
const prefixEnd = html.indexOf(";", prefixStart);
runInContext("this.__PREFIXES = " + html.slice(prefixStart + "const I18N_PREFIXES = ".length, prefixEnd) + ";", ctx);
const PREFIXES = ctx.__PREFIXES;

// --- 2. 獨立核對：JSON.parse 第二路徑深比對 --------------------------------
const parsed = JSON.parse(i18nLiteral);
let mismatches = 0;
const mismatchLines = [];
function check(cond, msg) {
  if (!cond) { mismatches++; mismatchLines.push("MISMATCH: " + msg); }
}
check(JSON.stringify(Object.keys(parsed).sort()) === JSON.stringify(Object.keys(I18N).sort()),
  "language set differs between vm-eval and JSON.parse");
for (const lang of Object.keys(I18N)) {
  const a = I18N[lang], b = parsed[lang] || {};
  const ka = Object.keys(a), kb = Object.keys(b);
  check(ka.length === kb.length, `${lang}: key count vm=${ka.length} parse=${kb.length}`);
  for (const k of ka) {
    check(a[k] === b[k], `${lang}: value differs for key ${JSON.stringify(k)}`);
  }
}

// --- 3. 鍵集統計與差異（缺鍵＝母本回退源串行為，僅記錄不算錯） -------------
const langOrder = ["zh-TW", "zh-CN", "en", "ja", "ko", "de", "fr", "ru"];
const dictLangs = ["zh-TW", "en", "ja", "ko", "de", "fr", "ru"]; // zh-CN 為源串本身、無字典
const twKeys = new Set(Object.keys(I18N["zh-TW"]));
const keyCounts = {};
const missingVsTw = {};
for (const lang of dictLangs) {
  keyCounts[lang] = Object.keys(I18N[lang]).length;
  missingVsTw[lang] = [...twKeys].filter((k) => !(k in I18N[lang]));
}
// 前綴鍵必須在字典內才生效（母本 translateString 的前綴分支條件）。
for (const p of PREFIXES) {
  check(p in I18N["zh-TW"], `prefix ${JSON.stringify(p)} missing in zh-TW dict`);
}

// --- 4. Spot-check 已知鍵 ---------------------------------------------------
const spotChecks = [
  ["zh-TW", "轻点任意处开始校音", "點擊下方「開啟麥克風校音」開始檢測"],
  ["zh-TW", "调音", "調音"],
  ["en", "调音", "Tuner"],
  ["de", "调音", "Stimmen"],
  ["zh-TW", "乐团木鱼", "樂團木魚"],
  ["en", "基准音 ", "Ref "],
  ["zh-TW", "本调 --", "本調 --"],
  ["ru", "节拍器运行中", "Метроном работает"],
];
for (const [lang, key, expected] of spotChecks) {
  check(I18N[lang][key] === expected,
    `spot-check ${lang} ${JSON.stringify(key)}: got ${JSON.stringify(I18N[lang][key])}, want ${JSON.stringify(expected)}`);
}

// --- 5. Supplement 合併 ------------------------------------------------------
const supplementRaw = JSON.parse(readFileSync(supplementPath, "utf8"));
delete supplementRaw._comment;
const supplement = {}; // lang -> { source: value }
for (const [source, perLang] of Object.entries(supplementRaw)) {
  for (const [lang, value] of Object.entries(perLang)) {
    if (!langOrder.includes(lang) || lang === "zh-CN") {
      check(false, `supplement ${JSON.stringify(source)}: unexpected lang ${lang}`);
      continue;
    }
    (supplement[lang] ||= {})[source] = value;
  }
  // supplement 鍵不得與母本字典鍵重疊（重疊時以字典為準並記錄）。
  if (source in I18N["zh-TW"]) {
    check(false, `supplement key ${JSON.stringify(source)} duplicates a master dict key`);
  }
}
const supplementCounts = {};
for (const lang of dictLangs) supplementCounts[lang] = Object.keys(supplement[lang] || {}).length;

// --- 6. 輸出 ------------------------------------------------------------------
const out = {
  version: 1,
  sourceLanguage: "zh-CN",
  defaultLanguage: "zh-TW",
  languages: langOrder,
  prefixes: PREFIXES,
  dict: I18N,
  supplement,
};
writeFileSync(outPath, JSON.stringify(out, null, 2) + "\n", "utf8");

const report = [
  "=== i18n 字典抽取核對報告 ===",
  `母本: ${htmlPath}`,
  `字典語言: ${dictLangs.join(", ")}（zh-CN 為源串本身、無字典）`,
  `逐語鍵數: ${dictLangs.map((l) => `${l}=${keyCounts[l]}`).join(" ")}`,
  `前綴鍵: ${PREFIXES.length} 條`,
  ...dictLangs.filter((l) => l !== "zh-TW").map(
    (l) => `缺鍵（回退源串，母本既定行為）${l}: ${missingVsTw[l].length} 條`),
  `supplement 原生專屬字串: ${Object.keys(supplementRaw).length} 條源串；逐語 ${dictLangs.map((l) => `${l}=${supplementCounts[l] || 0}`).join(" ")}`,
  `vm 求值 vs JSON.parse 深比對＋spot-check 不一致: ${mismatches}`,
  ...(mismatches ? ["--- 不一致明細 ---", ...mismatchLines] : []),
].join("\n") + "\n";
writeFileSync(reportPath, report, "utf8");
console.log(`dict keys: ${JSON.stringify(keyCounts)}; prefixes=${PREFIXES.length}; supplement sources=${Object.keys(supplementRaw).length}; mismatches=${mismatches}`);
