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
        case .dark: return Color(red: 38 / 255, green: 38 / 255, blue: 42 / 255)
        case .pit: return Color(red: 26 / 255, green: 9 / 255, blue: 9 / 255)
        }
    }

    /// 全 App 統一的玻璃配方（對齊 iOS 27 系統玻璃）：
    /// tint alpha = 0.05 + 0.36t（t = (不透明度−8)/88，
    /// 預設 50 → ≈0.22）。interactive 版供「整體即玻璃」
    /// 的按鍵本體（頂欄圓鈕等），按壓形變由玻璃本體給出。
    /// 【返修批2】alpha 曲線整體上調：舊版 0.02+0.34t 在
    /// 近黑頁面上玻璃與背景幾乎同色，實機看「完全沒有
    /// 玻璃感」（Laurent 點名偏好頁）；深色 tint 色版本身
    /// 亦提亮至 #26262A，讓卡面與頁面底色拉開層次。
    func glass(_ opacity: Int, interactive: Bool = false) -> Glass {
        let t = min(1, max(0, (Double(opacity) - 8) / 88))
        let base = Glass.regular.tint(glassTintBase.opacity(0.03 + 0.24 * t))
        return interactive ? base.interactive() : base
    }

    /// 選中鏡片的玻璃（返修批3・嚴格 iOS 27 標準）：無 tint
    /// 的系統真玻璃——返修批2 的白 tint（深 0.26／淺 0.85）
    /// 在實機讀作不透明的扁平灰白膠囊，Laurent 點名「不
    /// 是真液態玻璃，不是透明」。iOS 27 系統分段鏡片本體
    /// 即無染色 .regular 玻璃：透明度、邊緣折射、鏡面高光
    /// 全由 glassEffect 本體按背後內容即時算出，任何 tint
    /// 都只會把它推向塑料。淺色下系統玻璃自帶亮面，深字
    /// 成立；深色下為清透暗玻璃，近白字成立。
    var lensGlass: Glass {
        .regular.interactive()
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
        GlassEffectContainer(spacing: 0) {
            GeometryReader { geo in
                let count = max(1, options.count)
                let segW = (geo.size.width - 6) / CGFloat(count)
                let selCenter = 3 + segW * (CGFloat(selectedIndex) + 0.5)
                let lensCenter = dragX.map {
                    min(max($0, 3 + segW / 2), geo.size.width - 3 - segW / 2)
                } ?? selCenter
                ZStack(alignment: .leading) {
                    // 鏡片：無 tint 真玻璃＋glassEffectID morph；
                    // 幾何內縮（寬 segW−4、高 height−2、上下
                    // 置中），不凸出軌道。拖動形變：系統
                    // .interactive() 本體形變＋速度拉伸疊加。
                    Capsule()
                        .fill(.clear)
                        .frame(width: segW - 4, height: height - 2)
                        .glassEffect(theme.lensGlass, in: Capsule())
                        .glassEffectID("lens", in: glassNS)
                        .shadow(color: Color.black.opacity(theme.isDark ? 0.18 : 0.10),
                                radius: 3, x: 0, y: 1)
                        .scaleEffect(x: 1 + stretch, y: 1 - stretch * 0.35)
                        .offset(x: lensCenter - (segW - 4) / 2, y: 4)
                        .animation(pressing ? nil
                                   : .spring(response: 0.38, dampingFraction: 0.82),
                                   value: lensCenter)
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
    }

    /// 整控件拖動（坐標為控件局部系，location.x 即軌道
    /// 座標）：鏡片 1:1 跟指、越格心即切換＋輕觸感；速度
    /// 拉伸給出果凍形變（快拖拉長至 +13%、縱向回縮），
    /// 放手 spring 歸位且拉伸回彈。玻璃本體的形變/折射
    /// 由 .interactive()＋glassEffectID morph 在切換與歸
    /// 位時給出（系統 iOS 27 行為）。
    private func segDrag(segW: CGFloat, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                pressing = true
                dragX = value.location.x
                let now = value.time.timeIntervalSince1970
                if let lx = lastDragX, now > lastDragT {
                    let v = abs(value.location.x - lx) / CGFloat(now - lastDragT)
                    stretch = min(0.13, v / 5200)
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
                withAnimation(.spring(response: 0.38,
                                      dampingFraction: 0.82)) {
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
                .shadow(color: Color.black.opacity(theme.isDark ? 0.28 : 0.15),
                        radius: 5, x: 0, y: 2)
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
