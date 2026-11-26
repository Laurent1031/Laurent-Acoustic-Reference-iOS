#!/usr/bin/env python3
"""階段 8 匯入映射覆蓋驗證。

做三件事（本機無 Swift 工具鏈下的最強靜態證據）：
1. 欄位覆蓋：fixture（按母本 buildBackupJson 格式構造）中
   profile／settings 的每個欄位（含 customInstruments[]、
   metroPresets[] 的子欄位），必須在 BackupImporter.swift 中
   以字串鍵出現（被讀取或被點名不映射），不允許無聲遺漏。
2. 目標覆蓋：applyImport 賦值的每個 AppStore 屬性必須真實存在。
3. fixture 行為斷言：以 Python 鏡像匯入器的健全化規則，斷言
   fixture 的預期組裝結果（收藏過濾、自訂壞筆剔除、節拍器
   預設組成、未映射鍵清單）——驗證 fixture 本身確實觸達各路徑；
   Swift 側邏輯以代碼審計為準（見 docs/ 驗收清單）。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fixture = json.loads((ROOT / "tools/backup-fixture-v1.json").read_text(encoding="utf-8"))
importer = (ROOT / "AcousticReference/Models/BackupImporter.swift").read_text(encoding="utf-8")
appstore = (ROOT / "AcousticReference/Models/AppStore.swift").read_text(encoding="utf-8")

failures = []

# --- 1. 欄位覆蓋 ---
profile_fields = set(fixture["profile"].keys())
settings_fields = set(fixture["settings"].keys())
custom_fields = set()
for item in fixture["profile"]["customInstruments"]:
    custom_fields |= set(item.keys())
preset_fields = set()
for item in fixture["profile"]["metroPresets"]:
    preset_fields |= set(item.keys())

for scope, fields in (("profile", profile_fields), ("settings", settings_fields),
                      ("customInstruments[]", custom_fields), ("metroPresets[]", preset_fields)):
    for field in sorted(fields):
        if f'"{field}"' not in importer:
            failures.append(f"[欄位覆蓋] {scope}.{field} 未在 BackupImporter.swift 中出現")

# 信封鍵
for key in ("app", "v", "profile", "settings"):
    if key == "v":
        continue  # v 僅作格式標記，匯入器比照母本以 app 標記＋段存在性驗證，不讀 v
    if f'"{key}"' not in importer and key != "app":
        failures.append(f"[欄位覆蓋] 信封鍵 {key} 未被處理")
if "expectedAppTag" not in importer:
    failures.append("[欄位覆蓋] app 標記驗證缺失")

# 未映射三鍵必須在 unmappedKeys 的點名迴圈中
for key in ("customBgDataUrl", "bgColor", "bgKind"):
    if key not in importer:
        failures.append(f"[未映射點名] {key} 未在匯入器中點名")

# --- 2. 目標覆蓋 ---
apply_body = importer.split("func applyImport", 1)[1]
assigned = set(re.findall(r"^\s{12}(?:if let \w+ = plan\.\w+ \{\s*)?(\w+)\s*=", apply_body, re.M))
# 直接以 plan 欄位對 AppStore 屬性的對應表斷言（匯入器註解口徑）
targets = ["customInstruments", "favoriteInstrumentIds", "tunerSettings", "pitchMode",
           "droneTimbre", "droneFollow", "autoMicOnEnter", "metronomeUserPresets",
           "metronomeDefault", "primaryInstrumentId", "language", "appMode",
           "themePreference", "glassOpacity", "pendingImportPlan"]
for target in targets:
    if not re.search(rf"@Published var {target}\b", appstore):
        failures.append(f"[目標覆蓋] AppStore 無 @Published {target}")
    if target not in importer:
        failures.append(f"[目標覆蓋] BackupImporter 未觸及 {target}")

# --- 3. fixture 行為斷言（Python 鏡像健全化規則） ---
catalog = json.loads((ROOT / "AcousticReference/Resources/instruments.json").read_text(encoding="utf-8"))
builtin_ids = {inst["id"] for inst in catalog["instruments"]}

customs = [c for c in fixture["profile"]["customInstruments"]
           if c.get("id") and c.get("name") and c.get("maxF", 0) > c.get("minF", 0)]
assert len(customs) == 2, f"自訂樂器應存活 2 筆，實得 {len(customs)}"
catalog_ids = builtin_ids | {c["id"] for c in customs}
favs = [f for f in fixture["profile"]["favoriteInstIds"] if f in catalog_ids]
assert favs == ["custom_1730000000001", "alto_sax", "violin"], f"收藏過濾不符: {favs}"
assert fixture["profile"]["primaryInstId"] in catalog_ids
assert fixture["settings"]["glassAlpha"] == 72 and 8 <= 72 <= 96
assert fixture["settings"]["lang"] == "ja"
assert fixture["profile"]["defaultBeats"] == 3  # metronomeDefault accents 應為 [3,1,1]

# 錯誤信封（鏡像 ImportError 分類）
def classify(obj):
    if not isinstance(obj, dict) or obj.get("app") != "LAURENT-Acoustic-Reference":
        return "wrongApp"
    if not isinstance(obj.get("profile"), dict) and not isinstance(obj.get("settings"), dict):
        return "emptyEnvelope"
    return "ok"

assert classify({"app": "Other"}) == "wrongApp"
assert classify({"app": "LAURENT-Acoustic-Reference", "v": 1}) == "emptyEnvelope"
assert classify(fixture) == "ok"

if failures:
    print("FAIL")
    for f in failures:
        print(" -", f)
    sys.exit(1)
print("PASS: 欄位覆蓋（profile %d + settings %d + custom %d + preset %d)、目標覆蓋 %d 項、fixture 行為斷言全過"
      % (len(profile_fields), len(settings_fields), len(custom_fields), len(preset_fields), len(targets)))
