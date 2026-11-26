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
        textMuted: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.34),
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
        if let customBackground {
            customBackgroundView(customBackground)
        } else {
            themedBackground
        }
    }

    /// 自訂背景層（母本 bgGradientFor／wpLayer 等價）：
    /// 純色 = 165° 線性漸層（+26 → 原色 → −54）＋左上
    /// 徑向高光（+46 淡出）；圖片 = 等比填滿裁切。
    @ViewBuilder
    private func customBackgroundView(_ bg: CustomBackground) -> some View {
        switch bg {
        case .color(let hex):
            ZStack {
                LinearGradient(
                    colors: [Self.shade(hex, 26), Color(hex: hex),
                             Self.shade(hex, -54)],
                    startPoint: UnitPoint(x: 0.08, y: 0),
                    endPoint: UnitPoint(x: 0.62, y: 1))
                RadialGradient(
                    colors: [Self.shade(hex, 46).opacity(0.85),
                             Self.shade(hex, 46).opacity(0)],
                    center: UnitPoint(x: 0.18, y: 0),
                    startRadius: 0, endRadius: 460)
            }
        case .image(let data):
            if let uiImage = UIImage(data: data) {
                GeometryReader { geo in
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
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

extension TunerTheme {
    /// 玻璃 tint 色版：淺＝白、深＝#1C1C1E、樂池＝深紅黑。
    var glassTintBase: Color {
        switch kind {
        case .light: return .white
        case .dark: return Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
        case .pit: return Color(red: 26 / 255, green: 9 / 255, blue: 9 / 255)
        }
    }

    /// 全 App 統一的玻璃配方（對齊 iOS 27 系統玻璃）：
    /// tint alpha = 0.02 + 0.34t（t = (不透明度−8)/88，
    /// 預設 50 → ≈0.18）。interactive 版供「整體即玻璃」
    /// 的按鍵本體（頂欄圓鈕等），按壓形變由玻璃本體給出。
    func glass(_ opacity: Int, interactive: Bool = false) -> Glass {
        let t = min(1, max(0, (Double(opacity) - 8) / 88))
        let base = Glass.regular.tint(glassTintBase.opacity(0.02 + 0.34 * t))
        return interactive ? base.interactive() : base
    }
}

// MARK: - 液態玻璃（全量替換・2026-11-26 Laurent 指示）

/// 玻璃表面：系統 Liquid Glass 真折射（glassEffect）單層
/// 渲染，無任何自製覆蓋與描邊——Laurent 指示「液態玻璃
/// 部分全部替換、做好做精、尤其是細節」。
///
/// 沿革：第一版在折射層上壓白色覆蓋（×0.55）＋手繪描邊，
/// 實機成乳白磨砂（Laurent 特寫截圖自評「一坨」）；返修
/// 批降覆蓋至 ×0.30 仍屬貼補。本版全量替換為純系統玻璃：
/// 折射、高光、邊緣光暈全由 glassEffect 本體給出，這正是
/// Apple 液態玻璃與仿製材質的分野。
///
/// 不透明度（8–96）語義：只走 tint 單通道——alpha =
/// 0.02 + 0.34t（t = (值−8)/88）。預設 50 → ≈0.18，
/// 對齊 iOS 27 系統玻璃的清透濃度（重 tint 是仿製材質
/// 發塑料感的主因，Apple 官方亦明示 tint 須透）；拉高
/// 趨近實色、拉低趨近清透，全程不離折射本體。
/// interactive 不加於本背景層：按壓形變作用在控件本體
/// （GlassPressButtonStyle／鏡片），不加在襯底。
struct GlassSurface<S: Shape>: View {
    let shape: S
    let theme: TunerTheme
    let glassOpacity: Int

    var body: some View {
        shape
            .fill(.clear)
            .glassEffect(theme.glass(glassOpacity), in: shape)
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

// MARK: - 液態玻璃切換效果（裝機返修批・Laurent 指定）

/// 液態玻璃分段控件：選中態是一片真玻璃鏡片，於選項之間
/// 以 glassEffectID 在 GlassEffectContainer 內液態滑動
/// morph（iOS 26+ 系統效果），取代舊版實心藍填充。鏡片
/// 以 accent 32% 染色；選中文字走 textPrimary（淺色下為
/// 深字、深色下為亮字，雙主題對比皆成立），未選中走
/// textSecondary。容器僅用於本控件內部（小面積、形制
/// 單一，即官方文檔的標準用法）；頁面級大列已撤容器
/// （見 GlassSurface 註解的重影歸因）。
struct GlassSegmentedControl<Option: Hashable>: View {
    let options: [(option: Option, title: String, symbol: String?)]
    @Binding var selection: Option
    let theme: TunerTheme
    let glassOpacity: Int
    var fontSize: CGFloat = 13
    var height: CGFloat = 30
    var equalWidth: Bool = false
    @Namespace private var lensNamespace

    var body: some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(options, id: \.option) { item in
                    let active = selection == item.option
                    Button {
                        guard !active else { return }
                        withAnimation(.spring(response: 0.38,
                                              dampingFraction: 0.82)) {
                            selection = item.option
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if let symbol = item.symbol {
                                Image(systemName: symbol)
                                    .font(.system(size: fontSize - 1,
                                                  weight: .semibold))
                            }
                            Text(item.title)
                                .font(.system(size: fontSize, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(active ? theme.textPrimary
                                                : theme.textSecondary)
                        .padding(.horizontal, 11)
                        .frame(maxWidth: equalWidth ? .infinity : nil)
                        .frame(height: height)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if active {
                            Capsule()
                                .fill(.clear)
                                .glassEffect(
                                    .regular
                                        .tint(theme.accent.opacity(0.32))
                                        .interactive(),
                                    in: Capsule())
                                .glassEffectID("selection-lens",
                                               in: lensNamespace)
                        }
                    }
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(active ? [.isSelected] : [])
                }
            }
            .padding(3)
        }
        .background {
            GlassSurface(shape: Capsule(), theme: theme,
                         glassOpacity: glassOpacity)
        }
    }
}

/// 捲動列晶片的玻璃選中態（收藏／目標／速度預置等橫滑列
/// 內的晶片無法跨項 morph，改以逐片真玻璃＋accent 染色
/// ＋interactive 按壓形變呈現，與分段鏡片同語言）。
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
                .glassEffect(
                    .regular.tint(theme.accent.opacity(0.38)).interactive(),
                    in: Capsule())
                .overlay {
                    Capsule().strokeBorder(theme.accent.opacity(0.45),
                                           lineWidth: 1)
                }
        } else if bareUnselected {
            Color.clear
        } else {
            GlassSurface(shape: Capsule(), theme: theme,
                         glassOpacity: glassOpacity)
        }
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
struct GlassPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.10 : 0)
            .saturation(configuration.isPressed ? 1.12 : 1)
            .animation(.easeOut(duration: 0.25),
                       value: configuration.isPressed)
    }
}
