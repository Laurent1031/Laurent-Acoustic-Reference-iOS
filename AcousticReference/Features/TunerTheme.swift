import SwiftUI
import UIKit

/// 調音主畫面的設計 token，逐項對照母本 CSS 變量（index.html 行 151–198）。
///
/// 深色：--accent #0A84FF、--ok #30D158、--needle-color #F5F5F7、
/// --text-primary #F5F5F7、--text-secondary rgba(235,235,245,.6)、
/// --text-muted rgba(235,235,245,.34)。
/// 淺色：--accent #007AFF、--ok #34C759、--needle-color #1D1D1F、
/// --text-primary #1D1D1F、--text-secondary #334155、--text-muted #526071；
/// 音名準音色淺色另用 #248A3D（母本行 4645 的對比度修正）。
/// 偏差弧的「偏高」色 #FF9F0A 為母本 paintGauge 寫死值，雙主題相同。
///
/// 樂池暗紅（補強段新增第三態，母本無）：近黑底＋全套前景收進
/// 紅色譜、低亮度護夜視——accent 深紅、ok 亮朱紅（在單色紅
/// 環境中以亮度而非色相區分準音）、文字為暗紅白；節拍光色、
/// 推子填充、收藏星等原本的高亮色面一律改走 pit token，
/// 不得有漏網亮色（逐處核對見補強段報告的主題掃描表）。
/// pit 的 isDark = true：所有以 isDark 分支的透明度／材質選擇
/// 沿用深色行為，系統層另以 preferredColorScheme(.dark) 強制
/// 材質與選單走深色渲染（ContentView）。
struct TunerTheme {
    enum Kind: Sendable {
        case light
        case dark
        case pit
    }

    let kind: Kind
    var isDark: Bool { kind != .light }
    var isPit: Bool { kind == .pit }
    let accent: Color
    let ok: Color
    /// 音名大字在準音／鎖定時的顏色（淺色與 --ok 不同，見上）。
    let okText: Color
    let needle: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    /// 偏差弧偏高色（母本 #FF9F0A 寫死）。
    let sharp: Color
    /// 警示色（母本 --warn：深色 #FFD60A／淺色 #FF9500，行 157／196）：
    /// 收藏星標蹦出特效的火花色（母本 .burst-dot）。
    let warn: Color
    /// 削波警示色（補強段新增）：深 #FF453A／淺 #D70015（系統
    /// red 的深淺對應值）；pit 用亮橙紅，在單色紅環境中靠
    /// 色溫與亮度跳出。
    let clipWarning: Color
    /// 節拍圓點點亮漸層（母本 dotCell 寫死值）：強拍綠系、
    /// 一般藍系、預備拍琥珀系；pit 全部收進紅色譜。
    let beatStrongGradient: [Color]
    let beatNormalGradient: [Color]
    let countInGradient: [Color]
    /// 推子填充漸層（母本 .fader 填充：深色近白三段／淺色近白
    /// 兩段）；pit 改暗紅三段，避免整條亮白成為最亮色面。
    let faderFillColors: [Color]
    /// 推子圖示色：被填充覆蓋時（母本寫死 #0B4FD6）／未覆蓋時
    /// （深色白／淺色 #3A3A3C）；pit 改暗紅白系。
    let faderGlyphCovered: Color
    let faderGlyphUncovered: Color
    /// 收藏星色（母本寫死 #FFD60A，雙主題同）；pit 改暗琥珀。
    let favoriteStar: Color
    /// 自訂背景 payload（裝機返修批）：非 nil 時 background
    /// 改渲染自訂層；kind 沿解析時的淺／深基底（由背景亮度
    /// 判定，見 AppStore.customBackgroundIsLight）。
    var customBackground: CustomBackground? = nil

    enum CustomBackground: Sendable {
        case color(UInt32)
        case image(Data)
    }

    /// 依主題偏好與系統外觀解析（補強段）：.system 沿用母本
    /// 「隨系統」；.light/.dark 強制；.pit 樂池暗紅。
    static func resolve(preference: AppTheme, system: ColorScheme) -> TunerTheme {
        switch preference {
        case .pit: return .pit
        case .dark: return .dark
        case .light: return .light
        case .system: return system == .dark ? .dark : .light
        // 無 payload 的保底（正式路徑走四參數版）：隨系統。
        case .custom: return system == .dark ? .dark : .light
        }
    }

    /// 相容入口（舊呼叫點語義 = 跟隨系統）。
    static func resolve(_ scheme: ColorScheme) -> TunerTheme {
        resolve(preference: .system, system: scheme)
    }

    /// 自訂背景入口（裝機返修批）：preference == .custom 且
    /// 有 payload 時，以亮度判定選淺／深基底並掛上自訂層；
    /// 其餘情形與三參數版同。
    static func resolve(preference: AppTheme, system: ColorScheme,
                        customBackground: CustomBackground?,
                        customIsLight: Bool) -> TunerTheme {
        if preference == .custom, let customBackground {
            var theme = customIsLight ? TunerTheme.light : TunerTheme.dark
            theme.customBackground = customBackground
            return theme
        }
        return resolve(preference: preference, system: system)
    }

    static let dark = TunerTheme(
        kind: .dark,
        accent: Color(hex: 0x0A84FF),
        ok: Color(hex: 0x30D158),
        okText: Color(hex: 0x30D158),
        needle: Color(hex: 0xF5F5F7),
        textPrimary: Color(hex: 0xF5F5F7),
        textSecondary: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.6),
        // 【五維審計・排版項6】muted 0.34 在近黑底上對比
        // ≈2.4:1，承載資訊的小字（數據卡標籤/tile 標題）
        // 遠低於 AA。升 0.55（≈4.9:1）；純裝飾元素如需
        // 更弱層級，另以 opacity 疊加處理，不回降令牌。
        textMuted: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.55),
        sharp: Color(hex: 0xFF9F0A),
        warn: Color(hex: 0xFFD60A),
        clipWarning: Color(hex: 0xFF453A),
        beatStrongGradient: [Color(hex: 0x3CE068), Color(hex: 0x28B850)],
        beatNormalGradient: [Color(hex: 0x2B95FF), Color(hex: 0x0A84FF)],
        countInGradient: [Color(hex: 0xFFB340), Color(hex: 0xFF9F0A)],
        faderFillColors: [Color.white, Color.white, Color(hex: 0xEDF1F9)],
        faderGlyphCovered: Color(hex: 0x0B4FD6),
        faderGlyphUncovered: .white,
        favoriteStar: Color(hex: 0xFFD60A)
    )

    static let light = TunerTheme(
        kind: .light,
        accent: Color(hex: 0x007AFF),
        ok: Color(hex: 0x34C759),
        okText: Color(hex: 0x248A3D),
        needle: Color(hex: 0x1D1D1F),
        textPrimary: Color(hex: 0x1D1D1F),
        textSecondary: Color(hex: 0x334155),
        textMuted: Color(hex: 0x526071),
        sharp: Color(hex: 0xFF9F0A),
        warn: Color(hex: 0xFF9500),
        clipWarning: Color(hex: 0xD70015),
        beatStrongGradient: [Color(hex: 0x3CE068), Color(hex: 0x28B850)],
        beatNormalGradient: [Color(hex: 0x2B95FF), Color(hex: 0x0A84FF)],
        countInGradient: [Color(hex: 0xFFB340), Color(hex: 0xFF9F0A)],
        faderFillColors: [Color.white, Color(hex: 0xF7FAFF)],
        faderGlyphCovered: Color(hex: 0x0B4FD6),
        faderGlyphUncovered: Color(hex: 0x3A3A3C),
        favoriteStar: Color(hex: 0xFFD60A)
    )

    /// 樂池暗紅調色盤：整體亮度壓低、色相收進紅—橙紅段。
    /// ok 用最亮的朱紅 #FF5A36 與 accent 深紅拉開亮度差，
    /// 在單色環境中仍可一眼分辨準音；sharp 反用深紅（偏高側
    /// 弧段在暗背景上呈暗紅，與 ok 的亮形成對照）。
    static let pit = TunerTheme(
        kind: .pit,
        accent: Color(hex: 0xC62F3B),
        ok: Color(hex: 0xFF5A36),
        okText: Color(hex: 0xFF5A36),
        needle: Color(hex: 0xE8CFC8),
        textPrimary: Color(hex: 0xD8B4AC),
        // 【五維審計・排版項6】pit 次級文字原對比
        // secondary ≈2.9:1、muted ≈1.9:1（近乎不可讀）：
        // 基色提亮一檔 (216,150,140)→(226,170,160)、
        // alpha 升至 0.72／0.52。
        textSecondary: Color(red: 226 / 255, green: 170 / 255, blue: 160 / 255, opacity: 0.72),
        textMuted: Color(red: 226 / 255, green: 170 / 255, blue: 160 / 255, opacity: 0.52),
        sharp: Color(hex: 0x8E2F26),
        warn: Color(hex: 0xC98F3D),
        clipWarning: Color(hex: 0xFF7847),
        beatStrongGradient: [Color(hex: 0xFF6A4D), Color(hex: 0xD63A22)],
        beatNormalGradient: [Color(hex: 0xC74B3C), Color(hex: 0x8E2418)],
        countInGradient: [Color(hex: 0xE08A3C), Color(hex: 0xB85C1E)],
        faderFillColors: [Color(hex: 0x8E3B32), Color(hex: 0x6E2A24), Color(hex: 0x4A1D18)],
        faderGlyphCovered: Color(hex: 0xFFD9CF),
        faderGlyphUncovered: Color(hex: 0xD8B4AC),
        favoriteStar: Color(hex: 0xC98F3D)
    )

    /// 頁面背景：母本深色為頂部 #17171A → #000 的徑向漸層，
    /// 淺色為 #FFFFFF → #F2F2F7；以 RadialGradient 近似（玻璃真折射
    /// 與動態背景屬後續階段，此處只做靜態等價）。
    /// pit：頂部 #140404（近黑帶暗紅）→ #000。
    @ViewBuilder
    var background: some View {
        if let customBackground {
            customBackgroundView(customBackground)
        } else {
            themedBackground
        }
    }

    /// 自訂背景層（母本 bgGradientFor／wpLayer 等價，返修批4
    /// 可讀性重做）：
    /// 純色 = 165° 線性漸層（+16 → 原色 → −26，舊 −54 把底
    /// 部壓得過暗、與判定用亮度脫節）＋左上徑向高光（+32
    /// 淡出），再疊可讀性罩層：深底（白字）加黑 0.16、淺底
    /// （深字）加白 0.16——把中灰等死角底色推離對比交叉點，
    /// 任選底色字都不糊。
    /// 圖片 = 等比填滿＋放大 1.08 裁邊（防模糊邊緣透底）＋
    /// 高斯模糊 22＋降飽和 0.82，再按基底壓罩層（深底黑
    /// 0.38／淺底白 0.42）：照片只留氛圍，不再與文字搶
    /// 注意力（Laurent 點名「背景要模糊，不能造成閱讀障礙」）。
    @ViewBuilder
    private func customBackgroundView(_ bg: CustomBackground) -> some View {
        switch bg {
        case .color(let hex):
            ZStack {
                LinearGradient(
                    colors: [Self.shade(hex, 16), Color(hex: hex),
                             Self.shade(hex, -26)],
                    startPoint: UnitPoint(x: 0.08, y: 0),
                    endPoint: UnitPoint(x: 0.62, y: 1))
                RadialGradient(
                    colors: [Self.shade(hex, 32).opacity(0.7),
                             Self.shade(hex, 32).opacity(0)],
                    center: UnitPoint(x: 0.18, y: 0),
                    startRadius: 0, endRadius: 460)
                // 可讀性罩層：把底色整體推向字色相反側。
                (isDark ? Color.black.opacity(0.16)
                        : Color.white.opacity(0.16))
            }
        case .image(let data):
            if let uiImage = UIImage(data: data) {
                ZStack {
                    GeometryReader { geo in
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(1.08)
                            .saturation(0.82)
                            .blur(radius: 22)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                    (isDark ? Color.black.opacity(0.38)
                            : Color.white.opacity(0.42))
                }
            } else {
                Color.black
            }
        }
    }

    /// 母本 shadeHex 同義：三通道同加 amount 並鉗制 0–255。
    static func shade(_ hex: UInt32, _ amount: Int) -> Color {
        let r = Double(min(255, max(0, Int((hex >> 16) & 0xFF) + amount))) / 255
        let g = Double(min(255, max(0, Int((hex >> 8) & 0xFF) + amount))) / 255
        let b = Double(min(255, max(0, Int(hex & 0xFF) + amount))) / 255
        return Color(red: r, green: g, blue: b)
    }

    @ViewBuilder
    private var themedBackground: some View {
        switch kind {
        case .dark:
            ZStack {
                Color.black
                RadialGradient(
                    colors: [Color(hex: 0x17171A), Color.clear],
                    center: .top, startRadius: 0, endRadius: 560
                )
                // 【返修批8】環境微光（靜態）：真液態玻璃要
                // 有內容可折射——純黑底上系統玻璃只剩漫射
                // 霧面、讀作乳灰塑膠（批7 實機）。比照開屏
                // 三團柔光的語言，在頁底鋪極淡的藍／紫／青
                // 光暈（靜止圖層、零逐幀成本），玻璃的折射
                // 與邊緣高光由此承載；濃度壓在文字對比無感
                // 的範圍內。
                // 【返修批10】環境光整體加強＋補中央一團：
                // 批9 濃度下玻璃背後近乎純黑、無可折射內
                // 容，透明玻璃只剩輪廓；中央主顯示區補一
                // 團極淡 accent 光，令中部卡片也有色彩邊
                // 界可折射（文字對比經實測範圍仍無感）。
                RadialGradient(
                    colors: [Color(hex: 0x0A84FF).opacity(0.14), Color.clear],
                    center: UnitPoint(x: 0.10, y: 0.04),
                    startRadius: 0, endRadius: 340)
                RadialGradient(
                    colors: [Color(hex: 0xBF5AF2).opacity(0.10), Color.clear],
                    center: UnitPoint(x: 0.92, y: 0.36),
                    startRadius: 0, endRadius: 380)
                RadialGradient(
                    colors: [Color(hex: 0x64D2FF).opacity(0.08), Color.clear],
                    center: UnitPoint(x: 0.45, y: 1.02),
                    startRadius: 0, endRadius: 420)
                RadialGradient(
                    colors: [Color(hex: 0x0A84FF).opacity(0.05), Color.clear],
                    center: UnitPoint(x: 0.5, y: 0.44),
                    startRadius: 0, endRadius: 300)
            }
        case .pit:
            ZStack {
                Color.black
                RadialGradient(
                    colors: [Color(hex: 0x140404), Color.clear],
                    center: .top, startRadius: 0, endRadius: 560
                )
                // 【返修批8】同 dark 的環境微光，換樂池暗紅
                // 家族、濃度更收。
                RadialGradient(
                    colors: [Color(hex: 0x8E2F26).opacity(0.12), Color.clear],
                    center: UnitPoint(x: 0.10, y: 0.04),
                    startRadius: 0, endRadius: 340)
                RadialGradient(
                    colors: [Color(hex: 0xD63A22).opacity(0.05), Color.clear],
                    center: UnitPoint(x: 0.92, y: 0.40),
                    startRadius: 0, endRadius: 380)
            }
        case .light:
            ZStack {
                Color(hex: 0xF2F2F7)
                RadialGradient(
                    colors: [Color.white, Color.clear],
                    center: .top, startRadius: 0, endRadius: 560
                )
                // 【返修批8】淺色同鋪極淡微光，給 .clear
                // 鏡片與玻璃面留可折射的色彩邊界。
                RadialGradient(
                    colors: [Color(hex: 0x0A84FF).opacity(0.05), Color.clear],
                    center: UnitPoint(x: 0.10, y: 0.04),
                    startRadius: 0, endRadius: 340)
                RadialGradient(
                    colors: [Color(hex: 0xBF5AF2).opacity(0.04), Color.clear],
                    center: UnitPoint(x: 0.92, y: 0.36),
                    startRadius: 0, endRadius: 380)
            }
        }
    }
}

extension TunerTheme {
    /// 玻璃 tint 色版：淺＝白、深＝#1C1C1E、樂池＝深紅黑。
    var glassTintBase: Color {
        switch kind {
        case .light: return .white
        case .dark: return Color(red: 38 / 255, green: 38 / 255, blue: 42 / 255)
        case .pit: return Color(red: 26 / 255, green: 9 / 255, blue: 9 / 255)
        }
    }

    /// 全 App 統一的玻璃配方（對齊 iOS 27 系統玻璃）：
    /// tint alpha = 0.05 + 0.37t（t = (不透明度−8)/88，
    /// 預設 50 → ≈0.227；【返修批9】曲線，函數頭舊註曾
    /// 停留在批 8 值 0.02+0.16t，邏輯補查同步更正）。
    /// interactive 版供「整體即玻璃」
    /// 的按鍵本體（頂欄圓鈕等），按壓形變由玻璃本體給出。
    /// 【返修批2】alpha 曲線曾上調（0.03+0.24t）：舊版在
    /// 近黑頁面上玻璃與背景幾乎同色，實機看「完全沒有
    /// 玻璃感」；深色 tint 色版提亮至 #26262A 拉開層次。
    /// 【返修批8】曲線回调至 0.02+0.16t：批7 實機整體讀作
    /// 不透明乳灰塑膠（Laurent 點名要「真的液態玻璃、透
    /// 明」）——tint 是把系統玻璃推向塑料的主因；玻璃感改
    /// 由頁面底的微光漸層（themedBackground）提供可折射
    /// 內容承載，不再靠染色硬撐。
    func glass(_ opacity: Int, interactive: Bool = false) -> Glass {
        let t = min(1, max(0, (Double(opacity) - 8) / 88))
        // 【返修批10】透明優先（Laurent 裝機點名「要的是
        // 特別的透明」、批9 實機大面仍讀作扁平灰）：本體
        // 由 .regular 改 .clear 變體（與鏡片同源，幾乎無
        // 漫射霧面），tint 曲線同步壓低 0.05+0.37t →
        // 0.02+0.22t——玻璃感改由折射本體＋描邊／高光／
        // 虹彩三層光學（GlassSurface）與頁底環境光承載，
        // 不再靠染色。預設 50 → tint ≈0.125；8 → 0.02 趨
        // 近純水晶；96 → 0.24＋底填充 0.22 仍可讀。
        let base = Glass.clear.tint(glassTintBase.opacity(0.02 + 0.22 * t))
        return interactive ? base.interactive() : base
    }

    /// 選中鏡片的玻璃（返修批3・嚴格 iOS 27 標準；返修批8
    /// 改 .clear）：無 tint 的系統真玻璃——返修批2 的白
    /// tint（深 0.26／淺 0.85）在實機讀作不透明的扁平灰白
    /// 膠囊，Laurent 點名「不是真液態玻璃，不是透明」。
    /// 批3 去 tint 後用 .regular：透明度、邊緣折射、鏡面
    /// 高光全由 glassEffect 本體按背後內容即時算出。批7
    /// 實機 .regular 鏡片在深色軌道上仍呈一層乳灰（regular
    /// 自帶的漫射霧面），Laurent 再點名要透明——批8 改用
    /// .clear 變體：系統為多彩／媒體背景設計的清透玻璃，
    /// 幾乎無霧面、只留折射與邊緣高光，正是他給的液態玻
    /// 璃參考圖（厚玻璃本體、透明、內部折射、邊緣色散）
    /// 在系統玻璃裡的對應物。選中字 textPrimary 粗體在清
    /// 透鏡片上直接可讀（批7 實機選中字被乳灰鏡片吃掉的
    /// 問題隨之消失）。
    var lensGlass: Glass {
        .clear.interactive()
    }

    // MARK: - 返修批9・液態玻璃組件系統（Laurent 的 iOS 27 規範）

    /// 漸變高光內描邊配色（規範一：1px、非對稱——左上亮
    /// 白鏡面反射 → 右下虹彩微光，模擬玻璃邊緣折射高
    /// 光）。系統玻璃自帶邊緣光暈，此描邊補足其在深色
    /// 頁底上的鏡面定義；pressed 提亮＝規範三的激活態
    /// 「增強內部冷光、微凹折射」。
    func glassStrokeColors(pressed: Bool = false) -> [Color] {
        // 【五維審計・設計項6】pit 分支（原只分深/淺，pit
        // 沿用深色藍紫虹彩——違反卷首 pit 紀律「不得有漏
        // 網亮色」）：白光段改暖紅白、虹彩段改朱紅/琥珀。
        if isPit {
            let warmWhite = Color(red: 0.91, green: 0.81, blue: 0.78)
            return [warmWhite.opacity(pressed ? 0.58 : 0.38),
                    warmWhite.opacity(0.10),
                    Color(red: 1.0, green: 0.42, blue: 0.30)
                        .opacity(pressed ? 0.28 : 0.17),
                    Color(red: 0.88, green: 0.54, blue: 0.24).opacity(0.12),
                    warmWhite.opacity(0.05)]
        }
        if isDark {
            // 【返修批10】深色描邊整體提亮（首站 0.40→0.55、
            // 虹彩 0.18→0.22）：批9 實機邊緣定義不足、玻璃
            // 輪廓在近黑底上消失，鏡面邊是透明玻璃在深底
            // 上成立的主因。
            return [Color.white.opacity(pressed ? 0.78 : 0.55),
                    Color.white.opacity(0.12),
                    Color(red: 0.62, green: 0.55, blue: 1.0)
                        .opacity(pressed ? 0.36 : 0.22),
                    Color(red: 0.40, green: 0.85, blue: 1.0).opacity(0.14),
                    Color.white.opacity(0.06)]
        }
        return [Color.white.opacity(pressed ? 0.95 : 0.80),
                Color.white.opacity(0.28),
                Color(red: 0.62, green: 0.55, blue: 1.0).opacity(0.22),
                Color.white.opacity(0.10)]
    }

    var glassStrokeGradient: LinearGradient {
        LinearGradient(colors: glassStrokeColors(),
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 按壓態描邊（與無參屬性同名易混，獨立命名）。
    func glassPressedStrokeGradient(_ pressed: Bool) -> LinearGradient {
        LinearGradient(colors: glassStrokeColors(pressed: pressed),
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 虹彩散射（規範二）：玻璃內部的流體色彩——左上藍
    /// →中段紫→右下青，極低 alpha 只給色溫不給形狀，避
    /// 免死板純色毛玻璃。
    var glassIridescentWash: LinearGradient {
        // 【返修批10】散射 alpha 深 0.055→0.08、淺
        // 0.045→0.06：批9 實機幾乎不可見，流動感不出。
        let a = isDark ? 0.08 : 0.06
        // pit 變體（同描邊理由）：紅→朱紅→琥珀。
        if isPit {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.35, blue: 0.22).opacity(a),
                         Color(red: 0.85, green: 0.23, blue: 0.13).opacity(a * 0.8),
                         Color(red: 0.88, green: 0.54, blue: 0.24).opacity(a * 0.7),
                         Color.clear],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(
            colors: [Color(red: 0.04, green: 0.52, blue: 1.0).opacity(a),
                     Color(red: 0.75, green: 0.35, blue: 0.95).opacity(a * 0.8),
                     Color(red: 0.39, green: 0.82, blue: 1.0).opacity(a * 0.7),
                     Color.clear],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 左上徑向高光：日光折射的主光斑（淺色模式＝清透
    /// 水波高光、深色模式＝深邃流光，alpha 隨主題）。
    /// pit 用暖紅白（同 textPrimary 色溫），不用純白。
    var glassRadialHighlight: RadialGradient {
        let base: Color = isPit
            ? Color(red: 0.91, green: 0.81, blue: 0.78) : .white
        return RadialGradient(
            // 【返修批10】深色 0.10→0.15（同描邊理由）。
            colors: [base.opacity(isDark ? 0.15 : 0.32), .clear],
            center: .topLeading, startRadius: 0, endRadius: 190)
    }

    /// 不透明度底填充 alpha：與 glass() 的 tint 共同受
    /// 「玻璃不透明度」驅動。【返修批10】0.34t → 0.22t
    /// （透明優先，見 glass() 註）。
    func glassBaseFillAlpha(_ opacity: Int) -> Double {
        let t = min(1, max(0, (Double(opacity) - 8) / 88))
        return 0.22 * t
    }
}

/// 動畫令牌（專屬系統・動效分工）：全 App 動畫曲線的
/// 單一真源——果凍按壓／鏡片歸位／浮動進出／頁面切換／
/// 亮斑呼吸五族，任何新動畫先入此表再使用，禁止散落
/// 字面 spring。開屏彈簧族自成一格（SplashView 內，
/// 批7 定版單一彈簧敘事，不併入本表）。
enum AppMotion {
    /// 果凍按壓：按鍵、晶片、滑桿拇指。
    static let jelly = Animation.spring(response: 0.38, dampingFraction: 0.52)
    /// 鏡片歸位與 morph：分段鏡片、選中態位移。
    static let lens = Animation.spring(response: 0.38, dampingFraction: 0.82)
    /// 浮動元素進出：節拍器膠囊、浮層。
    static let capsule = Animation.spring(response: 0.32, dampingFraction: 0.9)
    /// 頁面模式切換交叉淡化。
    static let pageFade = Animation.easeInOut(duration: 0.25)
    /// 背景亮斑點亮／熄滅（母本 #pageGlow 時長）。
    static let glowIn = Animation.easeOut(duration: 0.12)
    static let glowOut = Animation.easeOut(duration: 0.3)
}

// MARK: - 液態玻璃（全量替換・2026-11-26 Laurent 指示）

/// 玻璃表面：系統 Liquid Glass 真折射（glassEffect）為
/// 本體——Laurent 指示「液態玻璃部分全部替換、做好做
/// 精、尤其是細節」。
///
/// 沿革：第一版在折射層上壓白色覆蓋（×0.55）＋手繪描邊，
/// 實機成乳白磨砂（Laurent 特寫截圖自評「一坨」）；返修
/// 批降覆蓋至 ×0.30 仍屬貼補；其後全量替換為純系統玻璃
/// 單層。返修批9 依 Laurent 的 iOS 27 組件規範在本體之
/// 上補回克制的自繪光學層（見下段）——與批1 的分野是總
/// 量：覆蓋不再是主體，只是鏡面定義的補筆。
///
/// 不透明度（8–96）語義（返修批10 改透明優先）：本體
/// .clear＋tint alpha = 0.02 + 0.22t（見 TunerTheme
/// .glass）＋底填充 0.22t 雙通道共同驅動。低端趨近
/// 純水晶、高端仍可讀，預設是清透濃度；玻璃的立體與
/// 流動感由光學層（散射／徑向高光／穹光／內影／描邊）
/// 與頁底環境光承載，不靠染色。
/// interactive 不加於本背景層：按壓形變作用在控件本體
/// （GlassPressButtonStyle／鏡片），不加在襯底。
///
/// 【返修批9・組件系統】在系統玻璃本體之上補 Laurent
/// 規範的自繪光學層（皆為靜態漸變、零逐幀成本）：虹
/// 彩散射（流體色彩）＋左上徑向高光（日光折射）＋1px
/// 漸變高光內描邊（左上鏡面→右下虹彩）。批1 的教訓
/// 是「白色覆蓋×0.55」把折射蓋死；本層總量克制（散
/// 射 ≤0.055、高光 ≤0.10 深／0.32 淺、描邊 1px），只
/// 補系統玻璃在深色頁底上欠缺的鏡面定義，不奪本體。
struct GlassSurface<S: InsettableShape>: View {
    let shape: S
    let theme: TunerTheme
    let glassOpacity: Int
    /// 【五維審計・設計 G9】系統「減少透明度」開啟時跳
    /// 過三層自繪裝飾（散射/高光/描邊），只留玻璃本體＋
    /// 底填充——裝飾層在降透明語境下只添噪聲。
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    var body: some View {
        shape
            .fill(theme.glassTintBase
                .opacity(theme.glassBaseFillAlpha(glassOpacity)))
            .glassEffect(theme.glass(glassOpacity), in: shape)
            .overlay {
                if !reduceTransparency {
                    shape.fill(theme.glassIridescentWash)
                        .blendMode(.overlay)
                }
            }
            .overlay {
                if !reduceTransparency {
                    shape.fill(theme.glassRadialHighlight)
                }
            }
            // 【返修批10・立體與流動感】凝膠穹光與底部內
            // 影：頂部一道自上而下衰減的穹面光（玻璃厚度
            // 的受光面）＋底部極淡內影（厚度陰影面）——
            // 批9 只有左上徑向一斑，大面仍讀作平面；穹光
            // 給出「微凸凝膠」的體積，Laurent 規範二點名
            // 要的立體感由此承載。皆靜態漸層、零逐幀成本。
            .overlay {
                if !reduceTransparency {
                    shape.fill(LinearGradient(
                        stops: [.init(color: (theme.isPit
                                    ? Color(red: 0.91, green: 0.81, blue: 0.78)
                                    : Color.white)
                                    .opacity(theme.isDark ? 0.10 : 0.16),
                                      location: 0),
                                .init(color: .clear, location: 0.45)],
                        startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay {
                if !reduceTransparency {
                    shape.fill(LinearGradient(
                        stops: [.init(color: .clear, location: 0.72),
                                .init(color: Color.black
                                    .opacity(theme.isDark ? 0.10 : 0.05),
                                      location: 1)],
                        startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay {
                if !reduceTransparency {
                    shape.strokeBorder(theme.glassStrokeGradient,
                                       lineWidth: 1)
                }
            }
    }
}

extension View {
    /// `.background(.ultraThinMaterial, in:)` 的玻璃不透明度
    /// 等價入口：全 App 玻璃背景一律經此，設定值即時驅動、
    /// 兩頁＋彈窗一致。
    func glassBackground<S: InsettableShape>(in shape: S, theme: TunerTheme,
                                             glassOpacity: Int) -> some View {
        background {
            GlassSurface(shape: shape, theme: theme, glassOpacity: glassOpacity)
        }
    }
}

// MARK: - 液態玻璃切換效果（裝機返修批・Laurent 指定）

/// 液態玻璃分段控件（返修批3・嚴格 iOS 27 標準重做）：
/// 整控件置於 GlassEffectContainer 內，選中鏡片為無 tint
/// 的系統真玻璃（theme.lensGlass、.interactive()）＋
/// glassEffectID——切換時玻璃本體在格位間液態 morph（邊
/// 緣折射由系統按 iOS 27 規範算出）。拖動手勢掛整控件
/// （任一格起手皆可拖，批2 已驗證的命中方式）：鏡片 1:1
/// 跟指、越格心即切換；速度感知各向異性拉伸疊加形變
/// （快拖拉長至 +13%、縱向回縮），放手 spring 歸位、拉
/// 伸回彈——形變不依賴命中鏡片本體，整控件拖動皆有。
/// 批2 的白 tint 鏡片（深 0.26／淺 0.85）在實機是不透
/// 明扁平灰膠囊，Laurent 點名「不是真液態玻璃、不是透
/// 明」——本版去 tint、去重陰影，鏡片幾何嚴格內縮於軌
/// 道（寬 segW−4、高 height−2、上下置中；批2 鏡片與軌
/// 道同高＋陰影外擴，設定頁實機凸出軌道）。選中字
/// textPrimary 粗體、未選中 textSecondary，全主題字色
/// （不讀裝置外觀，sheet 內亦成立）。版面恆等分，呼叫
/// 端須給定寬度。
struct GlassSegmentedControl<Option: Hashable>: View {
    let options: [(option: Option, title: String, symbol: String?)]
    @Binding var selection: Option
    let theme: TunerTheme
    let glassOpacity: Int
    var fontSize: CGFloat = 13
    var height: CGFloat = 30
    /// 舊參數保留相容（版面恆等分，見類註解）。
    var equalWidth: Bool = false
    @Namespace private var glassNS
    @State private var dragX: CGFloat?
    @State private var pressing = false
    @State private var stretch: CGFloat = 0
    @State private var lastDragX: CGFloat?
    @State private var lastDragT: TimeInterval = 0

    private var selectedIndex: Int {
        options.firstIndex { $0.option == selection } ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let count = max(1, options.count)
            let segW = (geo.size.width - 6) / CGFloat(count)
            let selCenter = 3 + segW * (CGFloat(selectedIndex) + 0.5)
            let lensCenter = dragX.map {
                min(max($0, 3 + segW / 2), geo.size.width - 3 - segW / 2)
            } ?? selCenter
            ZStack(alignment: .leading) {
                // 【返修批10・選中文字重影修復】GlassEffect
                // Container 只包鏡片本體，標籤列移到容器之
                // 外（鏡片之上）：批9 標籤與鏡片同處容器
                // 內，鏡片折射取樣把身後的選中標籤一併採
                // 入，實機選中文字呈「本體＋折射鬼影」上
                // 下錯位雙影（Laurent 截圖三處分段皆然）。
                // 標籤離開玻璃背景層後不再被取樣，雙影消
                // 除；morph 只作用於容器內的鏡片，不受影響。
                GlassEffectContainer(spacing: 0) {
                    ZStack(alignment: .leading) {
                        // 鏡片：無 tint 真玻璃（.clear，見
                        // theme.lensGlass）＋glassEffectID
                        // morph；幾何內縮（寬 segW−4、高
                        // height−2、垂直置中）。拖動形變：
                        // 系統 .interactive() 本體形變＋速度
                        // 拉伸疊加（批10 改水滴形變，見
                        // segDrag）。
                        Capsule()
                            .fill(.clear)
                            .frame(width: segW - 4, height: height - 2)
                            .glassEffect(theme.lensGlass, in: Capsule())
                            .glassEffectID("lens", in: glassNS)
                            // 【返修批9】鏡片補漸變高光描邊
                            // （規範一/三）：.clear 鏡片本體
                            // 在深色軌道上邊緣定義不足；1px
                            // 非對稱描邊給鏡面邊，拖動中
                            // （pressing）提亮＝激活態內部冷光。
                            .overlay {
                                Capsule().strokeBorder(
                                    theme.glassPressedStrokeGradient(pressing),
                                    lineWidth: 1)
                            }
                            .scaleEffect(x: 1 + stretch, y: 1 - stretch * 0.35)
                            .offset(x: lensCenter - (segW - 4) / 2, y: 0)
                            .animation(pressing ? nil
                                       : AppMotion.lens,
                                       value: lensCenter)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                HStack(spacing: 0) {
                        ForEach(options, id: \.option) { item in
                            let active = selection == item.option
                            HStack(spacing: 5) {
                                if let symbol = item.symbol {
                                    Image(systemName: symbol)
                                        .font(.system(size: fontSize - 1,
                                                      weight: .semibold))
                                }
                                Text(item.title)
                                    .font(.system(size: fontSize,
                                                  weight: active ? .bold : .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(active ? theme.textPrimary
                                                    : theme.textSecondary)
                            .frame(width: segW, height: height)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selection != item.option {
                                    selection = item.option
                                    HapticsEngine.shared.tap(milliseconds: 4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 3)
            }
            .contentShape(Capsule())
            .gesture(segDrag(segW: segW, count: count))
        }
        .frame(height: height + 6)
        .background {
            GlassSurface(shape: Capsule(), theme: theme,
                         glassOpacity: glassOpacity)
        }
        .accessibilityElement()
        .accessibilityLabel(options[selectedIndex].title)
        .accessibilityAdjustableAction { direction in
            let next: Int
            switch direction {
            case .increment:
                next = min(selectedIndex + 1, options.count - 1)
            case .decrement:
                next = max(selectedIndex - 1, 0)
            @unknown default:
                return
            }
            if options[next].option != selection {
                selection = options[next].option
            }
        }
        // 【五維審計 F-4／專屬規範 S-6】手勢被系統取消
        // （來電/系統手勢搶占）時 onEnded 不送達：視圖
        // 消失時歸零按壓/拖曳態，防鏡片動畫恆 nil、
        // 偏移凍結。
        .onDisappear {
            pressing = false
            dragX = nil
            stretch = 0
            lastDragX = nil
            lastDragT = 0
        }
    }

    /// 整控件拖動（坐標為控件局部系，location.x 即軌道
    /// 座標）：鏡片 1:1 跟指、越格心即切換＋輕觸感。
    /// 【返修批10・水滴形變】Laurent 點名鏡片拖動要「像
    /// 拖動水滴一樣、有形變」：速度拉伸上限 +13%→+22%
    /// （縱向回縮 −0.35 倍率不變），且拉伸值經低阻尼
    /// spring（0.22/0.55）平滑跟隨——形變滯後於手指、
    /// 帶過衝晃動，即表面張力的黏滯感；放手以果凍彈簧
    /// （AppMotion.jelly）歸零，形變流體回彈。玻璃本體
    /// 的形變/折射由 .interactive()＋glassEffectID
    /// morph 在切換與歸位時給出（系統 iOS 27 行為）。
    private func segDrag(segW: CGFloat, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                pressing = true
                dragX = value.location.x
                let now = value.time.timeIntervalSince1970
                if let lx = lastDragX, now > lastDragT {
                    let v = abs(value.location.x - lx) / CGFloat(now - lastDragT)
                    let target = min(0.22, v / 3400)
                    if abs(target - stretch) > 0.005 {
                        withAnimation(.spring(response: 0.22,
                                              dampingFraction: 0.55)) {
                            stretch = target
                        }
                    }
                }
                lastDragX = value.location.x
                lastDragT = now
                let idx = min(max(Int((value.location.x - 3) / segW), 0),
                              count - 1)
                if options[idx].option != selection {
                    selection = options[idx].option
                    HapticsEngine.shared.tap(milliseconds: 4)
                }
            }
            .onEnded { _ in
                pressing = false
                lastDragX = nil
                // 【返修批10】歸位動畫改果凍彈簧（低阻尼
                // 帶過衝）：鏡片與形變如水滴脫手後晃動收回。
                withAnimation(AppMotion.jelly) {
                    dragX = nil
                    stretch = 0
                }
            }
    }
}

/// 捲動列晶片的玻璃選中態（收藏／目標／速度預置等橫滑列
/// 內的晶片無法跨項拖動，鏡片改以逐片同款亮玻璃呈現，
/// 與分段鏡片同語言；返修批2 起廢 accent 藍 tint 與藍
/// 描邊，理由同 GlassSegmentedControl）。
struct GlassChipBackground: View {
    let selected: Bool
    let theme: TunerTheme
    let glassOpacity: Int
    /// 已在玻璃軌道內的晶片（樂器庫分類列）：未選中不另
    /// 鋪玻璃（避免玻璃疊玻璃發糊），只留選中鏡片。
    var bareUnselected: Bool = false

    var body: some View {
        if selected {
            Capsule()
                .fill(.clear)
                .glassEffect(theme.lensGlass, in: Capsule())
                // 【返修批9】與分段鏡片同款漸變高光描邊
                // （規範一）；投影減輕（0.28→0.20、半徑
                // 5→4）：批8 起的方向是去灰暈、留鏡面邊。
                .overlay {
                    Capsule().strokeBorder(theme.glassStrokeGradient,
                                           lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(theme.isDark ? 0.20 : 0.12),
                        radius: 4, x: 0, y: 2)
        } else if bareUnselected {
            Color.clear
        } else {
            GlassSurface(shape: Capsule(), theme: theme,
                         glassOpacity: glassOpacity)
        }
    }
}

/// 液態玻璃滑塊（返修批9・Laurent 組件規範「滑塊組
/// 件」）：玻璃軌＋accent 填充段＋玻璃拇指，拖動時拇
/// 指果凍形變。值經 Binding 逐幀寫回——呼叫端以
/// draft＋節流提交隔離全域狀態（見 SettingsView 的
/// glassDraft／bluetoothDraft），本組件只管呈現與手
/// 勢幾何。無障礙 adjustable 逐 step 增減（以一次完
/// 整編輯會話括住離散變更）。
/// 【返修批10・拇指改蘋果式】Laurent 裝機點名：拇指
/// 要蘋果系統滑桿的那種、不要圓形——改橫向膠囊
/// 46×28（iOS 系統玻璃滑桿拇指形制），尺寸同步放大
/// （舊圓拇指 ∅27 他評「大小不是這麼小」）；拖動形
/// 變改水滴式：橫向拉伸 1.10＋縱向壓扁 0.90、果凍
/// 彈簧回彈。
struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let theme: TunerTheme
    let glassOpacity: Int
    var accessibilityText: String = ""
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragging = false
    /// 【邏輯補查】手勢系統取消的前台回收點（見 body 尾）。
    @Environment(\.scenePhase) private var scenePhase
    /// 減少透明度（同 GlassSurface G9 處置）：跳過裝飾層。
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    /// 【返修批10】蘋果式膠囊拇指尺寸（見類註解）。
    private let thumbWidth: CGFloat = 46
    private let thumbHeight: CGFloat = 28
    private let trackHeight: CGFloat = 34

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, thumbWidth + 1)
            let thumbX = thumbWidth / 2
                + (width - thumbWidth) * CGFloat(fraction)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.glassTintBase.opacity(
                        theme.glassBaseFillAlpha(glassOpacity)))
                    .frame(height: 10)
                    .glassEffect(theme.glass(glassOpacity), in: Capsule())
                    .overlay {
                        if !reduceTransparency {
                            Capsule().strokeBorder(theme.glassStrokeGradient,
                                                   lineWidth: 1)
                        }
                    }
                Capsule()
                    .fill(LinearGradient(
                        colors: [theme.accent.opacity(0.85),
                                 theme.accent.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(thumbX, 10), height: 10)
                Capsule()
                    .fill(.clear)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .glassEffect(.clear.interactive(), in: Capsule())
                    .overlay {
                        if !reduceTransparency {
                            Capsule().strokeBorder(
                                theme.glassPressedStrokeGradient(dragging),
                                lineWidth: 1)
                        }
                    }
                    .overlay {
                        if !reduceTransparency {
                            Capsule().fill(theme.glassRadialHighlight)
                        }
                    }
                    .shadow(color: Color.black.opacity(
                        theme.isDark ? 0.30 : 0.18),
                            radius: 5, x: 0, y: 2)
                    // 【返修批10】拖動水滴形變（見類註解）。
                    .scaleEffect(x: dragging ? 1.10 : 1,
                                 y: dragging ? 0.90 : 1)
                    .animation(AppMotion.jelly, value: dragging)
                    .position(x: thumbX, y: trackHeight / 2)
            }
            .frame(height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging {
                            dragging = true
                            onEditingChanged(true)
                        }
                        setValue(fromX: g.location.x, width: width)
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    })
            .accessibilityElement(children: .ignore)
            .accessibilityValue(accessibilityText)
            .accessibilityAdjustableAction { direction in
                onEditingChanged(true)
                switch direction {
                case .increment:
                    value = min(range.upperBound, value + step)
                case .decrement:
                    value = max(range.lowerBound, value - step)
                @unknown default:
                    break
                }
                onEditingChanged(false)
            }
        }
        .frame(height: trackHeight)
        // 【五維審計 F-3／專屬規範 S-6】手勢被系統取消
        // 時 onEnded 不送達：消失時回收 editing 態，防
        // 設定頁 draft 回同步被永久擋下、尾值未提交。
        .onDisappear {
            if dragging {
                dragging = false
                onEditingChanged(false)
            }
        }
        // 【邏輯補查・低】手勢被系統取消（來電橫幅搶奪等）
        // 而視圖未消失時，onEnded 與 onDisappear 皆不送
        // 達、dragging 殘留（拇指維持放大、設定頁 editing
        // 旗標擋住 draft 回同步）：中斷必經場景離開
        // active，以回前台為第二回收點，語義同上。
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, dragging {
                dragging = false
                onEditingChanged(false)
            }
        }
    }

    private func setValue(fromX x: CGFloat, width: CGFloat) {
        let travel = max(width - thumbWidth, 1)
        let f = min(1, max(0, Double((x - thumbWidth / 2) / travel)))
        let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
        let snapped = (raw / step).rounded() * step
        let clamped = min(range.upperBound, max(range.lowerBound, snapped))
        if clamped != value { value = clamped }
    }
}

extension Color {
    /// #RRGGBB（ColorPicker 自選色回寫背景用；取 sRGB 三通道）。
    var hexString: String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// 全域按壓回饋（母本 .glass-press）：按下 brightness
/// 1.12＋saturate 1.12、0.25 s 緩動。原生多數按鍵此前用
/// .plain、無任何按壓回饋，按下如石沉大海——Laurent 實機
/// 「按不到或沒用」的一半是這個。此 style 只改亮度/飽和，
/// 不動版面；逐處以 .plain 換用（玻璃鏡片內部按鍵除外，
/// 其回饋由鏡片動畫本身給出）。
/// 【返修批9・果凍微交互】依 Laurent 組件規範三：按壓
/// 加凝膠彈性縮放（0.94）＋低阻尼 spring（0.52）——放
/// 手時帶一次 overshoot 回彈，如水滴受壓復原；亮度提
/// 升即規範的「按壓折射亮度增強」。
struct GlassPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .saturation(configuration.isPressed ? 1.15 : 1)
            .animation(AppMotion.jelly,
                       value: configuration.isPressed)
    }
}
