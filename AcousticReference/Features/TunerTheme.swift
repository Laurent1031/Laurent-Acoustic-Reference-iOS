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
struct TunerTheme {
    let isDark: Bool
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

    static func resolve(_ scheme: ColorScheme) -> TunerTheme {
        if scheme == .dark {
            return TunerTheme(
                isDark: true,
                accent: Color(hex: 0x0A84FF),
                ok: Color(hex: 0x30D158),
                okText: Color(hex: 0x30D158),
                needle: Color(hex: 0xF5F5F7),
                textPrimary: Color(hex: 0xF5F5F7),
                textSecondary: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.6),
                textMuted: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.34),
                sharp: Color(hex: 0xFF9F0A),
                warn: Color(hex: 0xFFD60A)
            )
        }
        return TunerTheme(
            isDark: false,
            accent: Color(hex: 0x007AFF),
            ok: Color(hex: 0x34C759),
            okText: Color(hex: 0x248A3D),
            needle: Color(hex: 0x1D1D1F),
            textPrimary: Color(hex: 0x1D1D1F),
            textSecondary: Color(hex: 0x334155),
            textMuted: Color(hex: 0x526071),
            sharp: Color(hex: 0xFF9F0A),
            warn: Color(hex: 0xFF9500)
        )
    }

    /// 頁面背景：母本深色為頂部 #17171A → #000 的徑向漸層，
    /// 淺色為 #FFFFFF → #F2F2F7；以 RadialGradient 近似（玻璃真折射
    /// 與動態背景屬後續階段，此處只做靜態等價）。
    @ViewBuilder
    var background: some View {
        if isDark {
            ZStack {
                Color.black
                RadialGradient(
                    colors: [Color(hex: 0x17171A), Color.clear],
                    center: .top, startRadius: 0, endRadius: 560
                )
            }
        } else {
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

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
