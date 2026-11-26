import SwiftUI

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

    /// 依主題偏好與系統外觀解析（補強段）：.system 沿用母本
    /// 「隨系統」；.light/.dark 強制；.pit 樂池暗紅。
    static func resolve(preference: AppTheme, system: ColorScheme) -> TunerTheme {
        switch preference {
        case .pit: return .pit
        case .dark: return .dark
        case .light: return .light
        case .system: return system == .dark ? .dark : .light
        }
    }

    /// 相容入口（舊呼叫點語義 = 跟隨系統）。
    static func resolve(_ scheme: ColorScheme) -> TunerTheme {
        resolve(preference: .system, system: scheme)
    }

    static let dark = TunerTheme(
        kind: .dark,
        accent: Color(hex: 0x0A84FF),
        ok: Color(hex: 0x30D158),
        okText: Color(hex: 0x30D158),
        needle: Color(hex: 0xF5F5F7),
        textPrimary: Color(hex: 0xF5F5F7),
        textSecondary: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.6),
        textMuted: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.34),
        sharp: Color(hex: 0xFF9F0A),
        warn: Color(hex: 0xFFD60A),
        clipWarning: Color(hex: 0xFF453A),
        beatStrongGradient: [Color(hex: 0x3CE068), Color(hex: 0x28B850)],
        beatNormalGradient: [Color(hex: 0x2B95FF), Color(hex: 0x0A84FF)],
        countInGradient: [Color(hex: 0xFFB340), Color(hex: 0xFF9F0A)],
        faderFillColors: [Color.white, Color(hex: 0xE9EFFC), Color(hex: 0xCCDAF6)],
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
        textSecondary: Color(red: 216 / 255, green: 150 / 255, blue: 140 / 255, opacity: 0.55),
        textMuted: Color(red: 216 / 255, green: 150 / 255, blue: 140 / 255, opacity: 0.34),
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
        switch kind {
        case .dark:
            ZStack {
                Color.black
                RadialGradient(
                    colors: [Color(hex: 0x17171A), Color.clear],
                    center: .top, startRadius: 0, endRadius: 560
                )
            }
        case .pit:
            ZStack {
                Color.black
                RadialGradient(
                    colors: [Color(hex: 0x140404), Color.clear],
                    center: .top, startRadius: 0, endRadius: 560
                )
            }
        case .light:
            ZStack {
                Color(hex: 0xF2F2F7)
                RadialGradient(
                    colors: [Color.white, Color.clear],
                    center: .top, startRadius: 0, endRadius: 560
                )
            }
        }
    }
}

// MARK: - 玻璃不透明度（階段 5 材質版 → 階段 6 真折射）

/// 玻璃表面（階段 6 升級）：系統 Liquid Glass 真折射
/// （glassEffect）為渲染主體——部署目標 iOS 27、CI runner
/// 為 Xcode 26.x（SDK ≥ 26，glassEffect 自 iOS 26 SDK 起
/// 可用），API 無條件可達，不需 availability 分支。
///
/// 玻璃不透明度（8–96）的語義映射：glassEffect 無 opacity
/// 參數，以兩條同向單調的通道保留可感差異——
/// 1. Glass tint：以主題表面色（深 (28,28,30)／淺白／pit
///    (26,9,9)）染色，alpha = 0.08 + 0.30t；
/// 2. 覆蓋層：階段 5 的母本 iOS 支曲線（t = (值−8)/88；
///    深 0.05+0.90t／淺 0.10+0.86t，pit 沿深色）× 0.55——
///    保留原曲線的相對節律，但讓出約一半權重給折射本體，
///    避免覆蓋層把真折射悶死。
/// 兩端行為：值 8 → tint 0.08＋覆蓋 ≈0.03–0.06，近全透、
/// 折射最強；值 96 → tint 0.38＋覆蓋 ≈0.52，呈濃色玻璃板、
/// 折射仍在邊緣與高光處可見。全程單調、兩端差異明確，
/// 與母本「不透明度」的心智模型一致（映射關係即此註解，
/// 屬有意取捨：原生無母本 blur／sat／bri 三維參數，階段 5
/// 已註明，階段 6 亦不冒充）。
///
/// 成簇分組：玻璃元素成排出現處（頂欄、調音頁首列／收藏
/// 列）由呼叫方以 GlassEffectContainer 包裹，系統得以統一
/// 合成、相鄰玻璃可流體相鄰渲染；單顆玻璃（膠囊、浮鈕）
/// 不需容器。interactive 不加於本背景層：按壓形變應作用在
/// 控件本體而非其背景襯底，加了只會讓襯底與內容脫步
/// （逐點取捨註明）。
struct GlassSurface<S: Shape>: View {
    let shape: S
    let theme: TunerTheme
    let glassOpacity: Int

    var body: some View {
        let t = min(1, max(0, (Double(glassOpacity) - 8) / 88))
        shape
            .fill(.clear)
            .glassEffect(glassVariant(t: t), in: shape)
            .overlay {
                shape.fill(opacityTint(t: t))
            }
    }

    /// 主題表面色（tint 與覆蓋層共用色版）。
    private var surfaceColor: Color {
        switch theme.kind {
        case .light:
            return .white
        case .dark:
            return Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
        case .pit:
            return Color(red: 26 / 255, green: 9 / 255, blue: 9 / 255)
        }
    }

    private func glassVariant(t: Double) -> Glass {
        Glass.regular.tint(surfaceColor.opacity(0.08 + 0.30 * t))
    }

    private func opacityTint(t: Double) -> Color {
        let curve: Double
        switch theme.kind {
        case .light:
            curve = 0.10 + 0.86 * t
        case .dark, .pit:
            curve = 0.05 + 0.90 * t
        }
        return surfaceColor.opacity(curve * 0.55)
    }
}

/// 階段 5 的材質版玻璃（回退保留）：ultraThinMaterial＋色版
/// 覆蓋。階段 6 起 GlassSurface 已切真折射，本結構保留給
/// 「效果不符」時的逐點回退用途——目前無呼叫點（全 App
/// 玻璃經 glassBackground 統一走 GlassSurface），保留是
/// 為裝機驗收若發現某處折射觀感不符，可單點切回而不動
/// 其餘 36 處（回退點須在該處註明理由）。
struct MaterialGlassSurface<S: Shape>: View {
    let shape: S
    let theme: TunerTheme
    let glassOpacity: Int

    var body: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(tint)
        }
    }

    private var tint: Color {
        let t = min(1, max(0, (Double(glassOpacity) - 8) / 88))
        switch theme.kind {
        case .light:
            return Color.white.opacity(0.10 + 0.86 * t)
        case .dark:
            return Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
                .opacity(0.05 + 0.90 * t)
        case .pit:
            return Color(red: 26 / 255, green: 9 / 255, blue: 9 / 255)
                .opacity(0.05 + 0.90 * t)
        }
    }
}

extension View {
    /// `.background(.ultraThinMaterial, in:)` 的玻璃不透明度
    /// 等價入口：全 App 玻璃背景一律經此，設定值即時驅動、
    /// 兩頁＋彈窗一致。
    func glassBackground<S: Shape>(in shape: S, theme: TunerTheme,
                                   glassOpacity: Int) -> some View {
        background {
            GlassSurface(shape: shape, theme: theme, glassOpacity: glassOpacity)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
