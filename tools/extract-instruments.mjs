// 樂器目錄程式化抽取：母本 ~/workspace/tuner-metronome/index.html
// → AcousticReference/Resources/instruments.json
//
// 方法：以字串定位切出母本的數據宣告段（const INSTRUMENTS …
// createDefaultProfile 之前，含 GUZHENG_TUNINGS／
// GUZHENG_KEY_SEMITONES／NOTE_NAMES），在 Node vm 內求值取得原始
// 數據物件（不手工謄抄任何一筆）；I18N 表以 JSON.parse 解析，
// zh-TW 顯示名一律查表（查無則保留源串並記錄於核對報告）。
// 核對：另以正則自母本原文逐種獨立抽 trans/minF/maxF 與 id 清單，
// 與抽取結果逐筆比對，摘要寫入 tools/extraction-report.txt。
import { readFileSync, writeFileSync } from "node:fs";
import { createContext, runInContext } from "node:vm";

const htmlPath = process.env.HOME + "/workspace/tuner-metronome/index.html";
const outPath = process.env.HOME +
  "/workspace/laurent-acoustic-reference-ios/AcousticReference/Resources/instruments.json";
const reportPath = process.env.HOME +
  "/workspace/laurent-acoustic-reference-ios/tools/extraction-report.txt";

const html = readFileSync(htmlPath, "utf8");

// --- 1. 切出數據段並求值 -------------------------------------------------
const segStart = html.indexOf("const INSTRUMENTS = [");
const segEnd = html.indexOf("function createDefaultProfile");
if (segStart < 0 || segEnd < 0 || segEnd <= segStart) {
  throw new Error("data segment not found");
}
const segment = html.slice(segStart, segEnd);
const ctx = createContext({});
runInContext(segment + "\n;this.__out = { INSTRUMENTS, GUZHENG_TUNINGS, GUZHENG_KEY_SEMITONES };", ctx);
const { INSTRUMENTS, GUZHENG_TUNINGS, GUZHENG_KEY_SEMITONES } = ctx.__out;

// --- 2. I18N zh-TW 查表 ---------------------------------------------------
const i18nStart = html.indexOf("const I18N = ");
if (i18nStart < 0) throw new Error("I18N not found");
let depth = 0, i18nEnd = -1;
for (let i = html.indexOf("{", i18nStart); i < html.length; i++) {
  if (html[i] === "{") depth++;
  else if (html[i] === "}") { depth--; if (depth === 0) { i18nEnd = i + 1; break; } }
}
const I18N = JSON.parse(html.slice(html.indexOf("{", i18nStart), i18nEnd));
const twTable = I18N["zh-TW"] || {};
const twMisses = [];
function tw(s) {
  if (typeof s !== "string") return s;
  if (Object.prototype.hasOwnProperty.call(twTable, s)) return twTable[s];
  twMisses.push(s);
  return s;
}

// --- 3. 分類（母本樂器庫分段鈕順序與源串，行 5521–5525） -------------------
const categories = [
  { id: "western_wind", name: tw("西洋管乐") },
  { id: "western_str", name: tw("弦乐键盘") },
  { id: "chinese", name: tw("民族乐团") },
  { id: "band", name: tw("现代乐队") },
  { id: "custom", name: tw("自订") },
];

// --- 4. 樂器陣列 ----------------------------------------------------------
const instruments = INSTRUMENTS.map((inst) => {
  const out = {
    id: inst.id,
    category: inst.cat,
    // catLabel 形如 "WOODWIND · 西洋木管"：I18N 表含複合全串鍵
    // （如 "KEYBOARD · 键盘乐器"），先查全串、未命中再分段查。
    categoryLabel: (() => {
      const full = String(inst.catLabel);
      if (Object.prototype.hasOwnProperty.call(twTable, full)) return twTable[full];
      const parts = full.split(" · ");
      return parts.length === 2 ? parts[0] + " · " + tw(parts[1]) : tw(full);
    })(),
    name: tw(inst.name),
    englishName: inst.en,
    keyName: inst.keyName,
    transposition: inst.trans,
    minFrequency: inst.minF,
    maxFrequency: inst.maxF,
    refTargets: Array.isArray(inst.refTargets)
      ? inst.refTargets.map((r) => ({ note: r.note, label: tw(r.label) }))
      : null,
    stringNotes: Array.isArray(inst.strings) ? inst.strings.slice() : null,
    isGuzheng: inst.isGuzheng === true,
    isCustom: false,
  };
  return out;
});

// --- 5. 古箏 ---------------------------------------------------------------
const guzheng = {
  // 母本調號選擇器順序（行 5284–5289）：D、G、C、F、A。
  keyOrder: ["D", "G", "C", "F", "A"],
  keySemitones: GUZHENG_KEY_SEMITONES,
  tunings: GUZHENG_TUNINGS,
};

const catalog = { version: 1, categories, instruments, guzheng };
writeFileSync(outPath, JSON.stringify(catalog, null, 2) + "\n", "utf8");

// --- 6. 獨立核對（正則自原文逐種抽取，與求值結果比對） ---------------------
const blockStart = segStart;
const blockEnd = html.indexOf("\n    ];", segStart);
const block = html.slice(blockStart, blockEnd);
const srcIds = [...block.matchAll(/\{ id: "([^"]+)"/g)].map((m) => m[1]);
const lines = [];
let mismatches = 0;
function check(cond, msg) {
  if (!cond) { mismatches++; lines.push("MISMATCH: " + msg); }
}
check(srcIds.length === instruments.length,
  `count: source ${srcIds.length} vs extracted ${instruments.length}`);
check(JSON.stringify(srcIds) === JSON.stringify(instruments.map((i) => i.id)),
  "id order differs");

for (const inst of instruments) {
  const lineRe = new RegExp(`\\{ id: "${inst.id}",[^\\n]*`);
  const m = block.match(lineRe);
  if (!m) { check(false, `${inst.id}: source line not found`); continue; }
  const src = m[0];
  const num = (re) => { const mm = src.match(re); return mm ? Number(mm[1]) : null; };
  const t = num(/trans: (-?\d+)/), mn = num(/minF: ([\d.]+)/), mx = num(/maxF: ([\d.]+)/);
  check(t === inst.transposition, `${inst.id}: trans src=${t} json=${inst.transposition}`);
  check(mn === inst.minFrequency, `${inst.id}: minF src=${mn} json=${inst.minFrequency}`);
  check(mx === inst.maxFrequency, `${inst.id}: maxF src=${mx} json=${inst.maxFrequency}`);
  const hasRT = /refTargets:/.test(src);
  check(hasRT === (inst.refTargets !== null), `${inst.id}: refTargets presence`);
  if (hasRT) {
    const srcNotes = [...src.matchAll(/note: "([^"]+)"/g)].map((x) => x[1]);
    check(JSON.stringify(srcNotes) === JSON.stringify(inst.refTargets.map((r) => r.note)),
      `${inst.id}: refTarget notes src=${srcNotes} json=${inst.refTargets.map((r) => r.note)}`);
  }
  const hasStrings = /strings:/.test(src);
  check(hasStrings === (inst.stringNotes !== null), `${inst.id}: strings presence`);
  lines.push(
    `${inst.id.padEnd(18)} cat=${inst.category.padEnd(13)} trans=${String(inst.transposition).padStart(4)} ` +
    `minF=${inst.minFrequency} maxF=${inst.maxFrequency} ref=${inst.refTargets ? inst.refTargets.length : "-"} ` +
    `strings=${inst.stringNotes ? inst.stringNotes.length : "-"} name=${inst.name}`);
}

// 古箏定弦核對：自原文逐調抽取並比對。
for (const key of Object.keys(GUZHENG_TUNINGS)) {
  const arr = GUZHENG_TUNINGS[key];
  check(arr.length === 21, `guzheng ${key}: ${arr.length} strings`);
}
const gzSrc = html.slice(html.indexOf("const GUZHENG_TUNINGS"), html.indexOf("const GUZHENG_KEY_SEMITONES"));
for (const key of Object.keys(GUZHENG_TUNINGS)) {
  const m = gzSrc.match(new RegExp(`${key}: \\[([^\\]]+)\\]`));
  const srcNotes = m ? [...m[1].matchAll(/"([^"]+)"/g)].map((x) => x[1]) : [];
  check(JSON.stringify(srcNotes) === JSON.stringify(GUZHENG_TUNINGS[key]),
    `guzheng tuning ${key} differs`);
}
check(JSON.stringify(GUZHENG_KEY_SEMITONES) === JSON.stringify({ C: 0, D: 2, F: 5, G: 7, A: 9 }),
  "guzheng key semitones differ from spec {C:0,D:2,F:5,G:7,A:9}");

const catCounts = {};
for (const i of instruments) catCounts[i.category] = (catCounts[i.category] || 0) + 1;

const report = [
  "=== 樂器目錄抽取核對報告 ===",
  `母本: ${htmlPath}`,
  `抽出樂器總數: ${instruments.length}`,
  `分類計數: ${JSON.stringify(catCounts)}`,
  `zh-TW 查表未命中（保留源串）: ${twMisses.length ? [...new Set(twMisses)].join(" | ") : "（無）"}`,
  `逐種比對不一致: ${mismatches}`,
  "--- 逐種清單 ---",
  ...lines.filter((l) => !l.startsWith("MISMATCH")),
  ...(mismatches ? ["--- 不一致明細 ---", ...lines.filter((l) => l.startsWith("MISMATCH"))] : []),
].join("\n") + "\n";
writeFileSync(reportPath, report, "utf8");
console.log(`extracted ${instruments.length} instruments, mismatches=${mismatches}`);
console.log("categories:", JSON.stringify(catCounts));
console.log("tw misses:", [...new Set(twMisses)].length);
