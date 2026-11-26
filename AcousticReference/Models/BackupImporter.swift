import Foundation

/// 網頁版數據備份匯入（階段 8，替代準備）：把母本「數據備份 ·
/// 導出備份」產出的 JSON 信封搬進原生 AppStateFile。
///
/// 信封格式（母本 buildBackupJson，index.html 行 11780 實查）：
/// `{ app: "LAURENT-Acoustic-Reference", v: 1, profile, settings }`
/// ——profile 為 localStorage `laurent_profile_v7` 的解析物件
/// （createDefaultProfile，行 6211 的形狀）、settings 為
/// `laurent_settings_v6`（saveAppSettings，行 8101 的形狀）；
/// 背景圖過大時母本會清空 settings.customBgDataUrl 並加
/// `bgOmitted: true`（原生不支援自訂背景，該欄恆不映射，見
/// unmappedKeys）。
///
/// 設計（失敗不動現有數據的原子性）：
/// 1. makePlan 先做信封級驗證（app 字串須符、profile／settings
///    至少一段為物件），再逐欄寬容映射成 ImportPlan——欄位級
///    壞值只跳過該欄並記 warning，不整份拒絕；
/// 2. plan 內的收藏／主樂器在組裝期即對「匯入後目錄」（內建＋
///    本次匯入的自訂樂器）完成健全化，apply 時不再二次判定；
/// 3. AppStore.applyImport 只在用戶於確認 sheet 按下「匯入」
///    後執行：有出現的段整段替換（profile 段的收藏／自訂樂器／
///    用戶預置／節拍器預設、settings 段各欄），未出現的段與
///    未映射的原生狀態（目前節拍器參數、顯示模式、演奏態等）
///    一律保留。plan 組裝失敗 → 拋錯，store 零寫入。
enum BackupImporter {

    static let expectedAppTag = "LAURENT-Acoustic-Reference"

    enum ImportError: Error, Equatable {
        /// 不是合法 JSON。
        case notJSON
        /// app 標記不符（不是本 App 的備份）。
        case wrongApp
        /// profile 與 settings 兩段皆缺或皆非物件。
        case emptyEnvelope
    }

    /// 映射完成的匯入計劃（全部為原生型別的最終值）。
    struct ImportPlan: Identifiable {
        let id = UUID()
        var hasProfile = false
        var hasSettings = false

        // profile 段（母本 createDefaultProfile 欄位）
        var primaryInstrumentId: String?
        var favoriteInstrumentIds: [String]?
        var customInstruments: [Instrument]?
        var a4: Double?
        var pitchMode: PitchMode?
        var damping: DampingProfile?
        var toleranceCents: Double?
        var noiseGate: NoiseGateProfile?
        var droneTimbre: DroneTimbre?
        var droneFollow: Bool?
        var temperament: Temperament?
        var justTonicPc: Int?
        var autoMicOnEnter: Bool?
        /// defaultBpm／defaultBeats／defaultNoteUnit／dottedBeat／
        /// defaultTimbre 五欄組成的整份快照（任一欄出現即組成，
        /// 缺欄以出廠值補——母本 profile 恆五欄齊全，此為寬容路徑）。
        var metronomeDefault: MetronomeSettings?
        var metronomeUserPresets: [MetronomePreset]?

        // settings 段（母本 saveAppSettings 欄位）
        var language: AppLanguage?
        var appMode: AppMode?
        var hapticsOn: Bool?
        var soundsOn: Bool?
        var themePreference: AppTheme?
        var glassOpacity: Int?

        /// 備份中有、原生有意不映射的鍵（逐鍵點名，確認 sheet 顯示）。
        var unmappedKeys: [String] = []
        /// 欄位級跳過／鉗制／回退的說明（確認 sheet 顯示）。
        var warnings: [String] = []

        /// 確認 sheet 的摘要行（組裝期以源串寫成，顯示時經 L10n）。
        var summaryLines: [String] = []
    }

    // MARK: - 組裝計劃

    static func makePlan(from data: Data) throws -> ImportPlan {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ImportError.notJSON
        }
        guard let envelope = raw as? [String: Any],
              (envelope["app"] as? String) == expectedAppTag
        else { throw ImportError.wrongApp }

        let profile = envelope["profile"] as? [String: Any]
        let settings = envelope["settings"] as? [String: Any]
        guard profile != nil || settings != nil else {
            throw ImportError.emptyEnvelope
        }

        var plan = ImportPlan()
        plan.hasProfile = profile != nil
        plan.hasSettings = settings != nil
        if (envelope["bgOmitted"] as? Bool) == true {
            plan.warnings.append("備份未包含背景圖（母本導出時已省略）")
        }

        // 自訂樂器先映射：收藏／主樂器的健全化要對匯入後目錄判定。
        var importedCustoms: [Instrument] = []
        if let profile {
            importedCustoms = mapCustomInstruments(profile["customInstruments"], plan: &plan)
            plan.customInstruments = importedCustoms
        }
        let catalogIds = Set(InstrumentCatalog.builtins.map(\.id))
            .union(importedCustoms.map(\.id))

        if let profile { mapProfile(profile, catalogIds: catalogIds, plan: &plan) }
        if let settings { mapSettings(settings, plan: &plan) }

        plan.summaryLines = buildSummary(plan)
        return plan
    }

    // MARK: profile 段

    private static func mapProfile(_ profile: [String: Any],
                                   catalogIds: Set<String>,
                                   plan: inout ImportPlan) {
        if let v = profile["defaultA4"] as? NSNumber {
            plan.a4 = min(450, max(430, v.doubleValue))
        }
        if let s = profile["pitchMode"] as? String {
            plan.pitchMode = PitchMode(rawValue: s)
            if plan.pitchMode == nil { plan.warnings.append("pitchMode 值無法識別，已跳過") }
        }
        if let s = profile["damping"] as? String {
            plan.damping = DampingProfile(rawValue: s)
            if plan.damping == nil { plan.warnings.append("damping 值無法識別，已跳過") }
        }
        if let v = profile["tolerance"] as? NSNumber {
            plan.toleranceCents = min(10, max(0.5, v.doubleValue))
        }
        if let s = profile["noiseGate"] as? String {
            plan.noiseGate = NoiseGateProfile(rawValue: s)
            if plan.noiseGate == nil { plan.warnings.append("noiseGate 值無法識別，已跳過") }
        }
        if let s = profile["droneTimbre"] as? String {
            plan.droneTimbre = DroneTimbre(rawValue: s)
            if plan.droneTimbre == nil { plan.warnings.append("droneTimbre 值無法識別，已跳過") }
        }
        if let v = profile["droneFollow"] as? Bool { plan.droneFollow = v }
        if let s = profile["temperament"] as? String {
            plan.temperament = Temperament(rawValue: s)
            if plan.temperament == nil { plan.warnings.append("temperament 值無法識別，已跳過") }
        }
        if let v = profile["justTonicPc"] as? NSNumber {
            plan.justTonicPc = ((v.intValue % 12) + 12) % 12
        }
        if let v = profile["autoMicOnEnter"] as? Bool { plan.autoMicOnEnter = v }

        // 收藏：只留匯入後目錄可解析的 id、去重保序；全滅時退回
        // 母本預設三件（與 AppStore.init 的健全化同一口徑）。
        if let rawFavs = profile["favoriteInstIds"] as? [Any] {
            var seen = Set<String>()
            var favs: [String] = []
            for item in rawFavs {
                guard let id = item as? String, catalogIds.contains(id),
                      seen.insert(id).inserted else { continue }
                favs.append(id)
            }
            if favs.isEmpty {
                favs = ["alto_sax", "piano", "violin"].filter { catalogIds.contains($0) }
                plan.warnings.append("備份收藏無法解析，已退回預設收藏")
            }
            plan.favoriteInstrumentIds = favs
        }

        // 主樂器：可解析才映射（apply 時同時設為選中樂器——母本
        // 匯入後重載即以 primary 為目前樂器，語義對齊）。
        if let s = profile["primaryInstId"] as? String {
            if catalogIds.contains(s) {
                plan.primaryInstrumentId = s
            } else {
                plan.warnings.append("primaryInstId 指向不存在的樂器，已跳過")
            }
        }

        // 節拍器預設參數（五欄）：任一欄出現即組成整份快照。
        let metroKeys = ["defaultBpm", "defaultBeats", "defaultNoteUnit",
                         "dottedBeat", "defaultTimbre"]
        if metroKeys.contains(where: { profile[$0] != nil }) {
            var metro = MetronomeSettings()
            if let v = profile["defaultBeats"] as? NSNumber {
                metro.beatsPerBar = min(12, max(1, v.intValue))
            }
            if let v = profile["defaultNoteUnit"] as? NSNumber {
                metro.beatUnit = [2, 4, 8, 16].contains(v.intValue) ? v.intValue : 4
            }
            if let v = profile["dottedBeat"] as? Bool { metro.dottedBeat = v }
            if let s = profile["defaultTimbre"] as? String,
               let timbre = MetronomeTimbre(rawValue: s) {
                metro.timbre = timbre
            }
            if let v = profile["defaultBpm"] as? NSNumber {
                metro.bpm = metro.clampedBpm(v.intValue)
            }
            metro.beatAccents = MetronomeSettings.defaultAccents(
                beats: metro.beatsPerBar, unit: metro.beatUnit)
            plan.metronomeDefault = metro
        }

        // 用戶節拍器預置（母本 metroPresets，行 7665 的形狀）。
        if let rawPresets = profile["metroPresets"] as? [Any] {
            var presets: [MetronomePreset] = []
            var seen = Set<String>()
            for item in rawPresets {
                guard let dict = item as? [String: Any],
                      let id = dict["id"] as? String, !id.isEmpty,
                      let name = dict["name"] as? String, !name.isEmpty,
                      seen.insert(id).inserted
                else { continue }
                let timbre = (dict["timbre"] as? String)
                    .flatMap { MetronomeTimbre(rawValue: $0) } ?? .woodblock
                presets.append(MetronomePreset(
                    id: id, name: name,
                    bpm: min(300, max(20, (dict["bpm"] as? NSNumber)?.intValue ?? 120)),
                    beats: min(12, max(1, (dict["beats"] as? NSNumber)?.intValue ?? 4)),
                    noteUnit: [2, 4, 8, 16].contains((dict["noteUnit"] as? NSNumber)?.intValue ?? 4)
                        ? ((dict["noteUnit"] as? NSNumber)?.intValue ?? 4) : 4,
                    subdivision: min(5, max(1, (dict["subdivision"] as? NSNumber)?.intValue ?? 1)),
                    timbre: timbre, builtin: false))
            }
            plan.metronomeUserPresets = presets
        }
    }

    /// 母本自訂樂器（行 7851 的形狀）：{id, cat, catLabel, name,
    /// en, keyName, trans, minF, maxF}——音域以頻率存（由 MIDI 上下限
    /// ×0.85／×1.15 換算，行 7862），原生 Instrument 同樣以頻率存，
    /// 直搬零換算。壞筆（缺 id／name、maxF ≤ minF）整筆跳過並記數。
    private static func mapCustomInstruments(_ raw: Any?,
                                               plan: inout ImportPlan) -> [Instrument] {
        guard let items = raw as? [Any] else { return [] }
        var result: [Instrument] = []
        var seen = Set<String>()
        var skipped = 0
        for item in items {
            guard let dict = item as? [String: Any],
                  let id = dict["id"] as? String, !id.isEmpty,
                  let name = dict["name"] as? String, !name.isEmpty,
                  let minF = (dict["minF"] as? NSNumber)?.doubleValue,
                  let maxF = (dict["maxF"] as? NSNumber)?.doubleValue,
                  maxF > minF,
                  seen.insert(id).inserted
            else { skipped += 1; continue }
            let category = (dict["cat"] as? String)
                .flatMap { InstrumentCategory(rawValue: $0) } ?? .custom
            let en = (dict["en"] as? String) ?? ""
            let trans = min(24, max(-24, (dict["trans"] as? NSNumber)?.intValue ?? 0))
            let pc = ((trans % 12) + 12) % 12
            let keyName = (dict["keyName"] as? String)
                ?? "1 = \(PitchMath.noteNames[pc])"
            result.append(Instrument(
                id: id,
                category: category,
                categoryLabel: (dict["catLabel"] as? String) ?? "CUSTOM · 自訂樂器",
                name: name,
                englishName: en.isEmpty ? "Custom" : en,
                keyName: keyName,
                transposition: trans,
                minFrequency: max(20, minF),
                maxFrequency: maxF,
                refTargets: nil, stringNotes: nil,
                isGuzheng: false, isCustom: true))
            if InstrumentCatalog.builtin(id: id) != nil {
                plan.warnings.append("自訂樂器 id 與內建樂器重複：\(id)（原生以自訂為先，與母本一致）")
            }
        }
        if skipped > 0 {
            plan.warnings.append("自訂樂器有 \(skipped) 筆格式不完整，已跳過")
        }
        return result
    }

    // MARK: settings 段

    private static func mapSettings(_ settings: [String: Any],
                                    plan: inout ImportPlan) {
        if let s = settings["lang"] as? String {
            plan.language = AppLanguage(rawValue: s)
            if plan.language == nil { plan.warnings.append("lang 值無法識別，已跳過") }
        }
        if let s = settings["mode"] as? String {
            plan.appMode = AppMode(rawValue: s)
            if plan.appMode == nil { plan.warnings.append("mode 值無法識別，已跳過") }
        }
        if let v = settings["hapticsOn"] as? Bool { plan.hapticsOn = v }
        if let v = settings["soundsOn"] as? Bool { plan.soundsOn = v }
        if let s = settings["themeMode"] as? String {
            switch s {
            case "system": plan.themePreference = .system
            case "light": plan.themePreference = .light
            case "dark": plan.themePreference = .dark
            case "custom":
                // 母本自訂背景（圖／色）原生未移植（階段 5 有意
                // 差異）：退回隨系統並點名，不靜默吞掉。
                plan.themePreference = .system
                plan.unmappedKeys.append("themeMode=custom（自訂背景）→ 已退回隨系統")
            default:
                plan.warnings.append("themeMode 值無法識別，已跳過")
            }
        }
        if let v = settings["glassAlpha"] as? NSNumber {
            plan.glassOpacity = min(96, max(8, v.intValue))
        }
        // 自訂背景三鍵：原生無對應功能，逐鍵點名不映射。
        for key in ["customBgDataUrl", "bgColor", "bgKind"]
        where settings[key] != nil {
            plan.unmappedKeys.append(key)
        }
    }

    // MARK: 摘要

    private static func buildSummary(_ plan: ImportPlan) -> [String] {
        var lines: [String] = []
        if plan.hasProfile {
            var parts: [String] = []
            if let favs = plan.favoriteInstrumentIds { parts.append("收藏 \(favs.count) 件") }
            if let customs = plan.customInstruments { parts.append("自訂樂器 \(customs.count) 件") }
            if let presets = plan.metronomeUserPresets { parts.append("節拍器預置 \(presets.count) 組") }
            if plan.metronomeDefault != nil { parts.append("節拍器預設參數") }
            parts.append("調音偏好")
            lines.append("個人資料段：" + parts.joined(separator: "、"))
        }
        if plan.hasSettings {
            lines.append("系統設定段：語言／外觀／玻璃／回饋開關")
        }
        // 摘要／警告／未映射說明為診斷性文字：組裝期即以繁中
        // 書寫、顯示端直顯不查表（與階段 5 的引擎錯誤原文豁免
        // 同一口徑）；sheet 的固定 UI 文字則走 L10n＋supplement。
        return lines
    }
}

// MARK: - 套用（用戶確認後才執行；段級整段替換、未映射段保留）

extension AppStore {
    /// 套用匯入計劃。各 @Published 賦值各自觸發 persist，淨效果
    /// 為一次完整狀態替換；套用前不做任何寫入，故確認前取消即
    /// 零副作用。順序：自訂樂器先行（收藏／主樂器解析依賴它）。
    func applyImport(_ plan: BackupImporter.ImportPlan) {
        // 調音偏好欄位級合成（跨段：profile 給 a4／阻尼／容差／
        // 噪聲門／律制／主音，settings 給震動／音效開關）：以現行
        // 值為底，只覆寫 plan 有值的欄；plan 欄位僅由其來源段
        // 填寫，故不需再按段設防。
        var tuner = tunerSettings
        if let a4 = plan.a4 { tuner.a4 = a4 }
        if let damping = plan.damping { tuner.damping = damping }
        if let tolerance = plan.toleranceCents { tuner.toleranceCents = tolerance }
        if let gate = plan.noiseGate { tuner.noiseGate = gate }
        if let temperament = plan.temperament { tuner.temperament = temperament }
        if let pc = plan.justTonicPc { tuner.justTonicPc = pc }
        if let haptics = plan.hapticsOn { tuner.hapticsOn = haptics }
        if let sounds = plan.soundsOn { tuner.soundsOn = sounds }
        tunerSettings = tuner

        if plan.hasProfile {
            if let customs = plan.customInstruments {
                customInstruments = customs
            }
            if let favs = plan.favoriteInstrumentIds {
                favoriteInstrumentIds = favs
            }
            if let mode = plan.pitchMode { pitchMode = mode }
            if let timbre = plan.droneTimbre { droneTimbre = timbre }
            if let follow = plan.droneFollow { droneFollow = follow }
            if let autoMic = plan.autoMicOnEnter { autoMicOnEnter = autoMic }
            if let presets = plan.metronomeUserPresets {
                metronomeUserPresets = presets
            }
            if let metroDefault = plan.metronomeDefault {
                metronomeDefault = metroDefault
            }
            if let primary = plan.primaryInstrumentId {
                primaryInstrumentId = primary
                selectInstrument(id: primary)
            }
        }
        if plan.hasSettings {
            if let language = plan.language { self.language = language }
            if let mode = plan.appMode { appMode = mode }
            if let theme = plan.themePreference { themePreference = theme }
            if let glass = plan.glassOpacity { glassOpacity = glass }
            // hapticsOn／soundsOn 在母本存於 settings 段、原生存於
            // tunerSettings：已在上方合成（plan 欄位不分段），此處
            // 不重複處理。
        }
        pendingImportPlan = nil
    }
}
