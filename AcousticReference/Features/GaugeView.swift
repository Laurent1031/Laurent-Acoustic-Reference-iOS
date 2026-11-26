import SwiftUI

/// 弧形錶盤：母本 SVG gauge（buildGauge／paintGauge，行 9749／9817）的
/// 等比移植。設計坐標恆為 320×190（viewBox），以單一 uniform scale
/// 映射到實際尺寸並置中——正圓不變形、刻度幾何在任何螢幕一致。
///
/// 幾何常數（母本 GAUGE）：cx 160、cy 174.8、r 144、maxDeg 62；
/// 角度 θ(c) = (c/50)·62 − 90（度），點 = (cx + r·cosθ, cy + r·sinθ)。
/// 元素與母本逐項對應：
/// - 容差帶：−tol…+tol 弧（r−1、線寬 3.5、ok 色、opacity 運行 0.5／停 0.3）；
/// - 偏差弧：0→clamped 弧（r−1、線寬 4.2；色：準音 ok／偏高 #FF9F0A／
///   偏低 accent；opacity 準音 0.75／否則 0.52；|cents| ≤ 0.6 或未運行隱藏）；
/// - 刻度：−50…+50 每 2¢ 一格（內徑：0 格 r−15、十位格 r−10、其餘 r−5；
///   線寬 2.8／1.7／1.0；|c| ≤ tol 用 ok 色、其餘 muted）；
/// - 數字標籤：十位格（0 除外）於 r−21、8.5pt 粗體等寬；
/// - 0 位冠標：向下三角（母本 polygon 三點原值），填 ok 色；
/// - 尾跡：兩層跟隨臂（線寬 2.2、opacity 0.15／0.07，未運行 0）；
/// - 定格針（#13）：同臂幾何，opacity 由 ViewModel 按時間給（0.35 起淡出）；
/// - 主針：臂長 r−3（線寬 2.8）、尾長 r×0.16（線寬 2.4、opacity 0.45）、
///   轂圓 r 5；針色：準音 ok／運行 accent／待機 needle。
struct GaugeView: View {
    let cents: Double
    let trail1Cents: Double
    let trail2Cents: Double
    let ghostCents: Double?
    let ghostOpacity: Double
    let micActive: Bool
    let inTune: Bool
    let tolerance: Double
    let theme: TunerTheme

    // 母本 GAUGE 常數。
    private static let cx: Double = 160
    private static let cy: Double = 174.8
    private static let r: Double = 144
    private static let maxDeg: Double = 62

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 320, geo.size.height / 190)
            let ox = (geo.size.width - 320 * s) / 2
            let oy = (geo.size.height - 190 * s) / 2

            ZStack {
                Canvas { ctx, _ in
                    var ctx = ctx
                    ctx.translateBy(x: ox, y: oy)
                    ctx.scaleBy(x: s, y: s)
                    drawGauge(in: &ctx)
                }
                // 數字標籤以 SwiftUI Text 疊加定位（不經 Canvas 縮放，
                // 字體大小 = 8.5 × s，確保縮放行為確定）。
                ForEach(Self.majorTicks.filter { $0 != 0 }, id: \.self) { c in
                    let p = Self.point(cents: Double(c), radius: Self.r - 21)
                    Text(c > 0 ? "+\(c)" : "\(c)")
                        .font(.system(size: 8.5 * s, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.textMuted)
                        .position(x: ox + p.x * s, y: oy + p.y * s)
                }
            }
        }
        .aspectRatio(320.0 / 190.0, contentMode: .fit)
    }

    private static let majorTicks = [-50, -40, -30, -20, -10, 0, 10, 20, 30, 40, 50]

    // MARK: - 幾何（母本 gaugePoint）

    private static func point(cents: Double, radius: Double) -> CGPoint {
        let rad = ((cents / 50) * maxDeg - 90) * Double.pi / 180
        return CGPoint(
            x: cx + radius * cos(rad),
            y: cy + radius * sin(rad)
        )
    }

    /// 弧線以 0.5¢ 步進取樣成折線（小弧段與母本 SVG 圓弧視覺等價）。
    private static func arcPath(c0: Double, c1: Double, radius: Double) -> Path {
        var path = Path()
        let steps = max(1, Int(ceil(abs(c1 - c0) / 0.5)))
        for i in 0...steps {
            let c = c0 + (c1 - c0) * Double(i) / Double(steps)
            let p = point(cents: c, radius: radius)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    /// 針臂：自中心沿 cents 方向長 length（母本以 rotate 群組實現，
    /// 此處以方向向量等價計算：端點 = point(cents, length) 的相對形式）。
    private static func armPath(cents: Double, length: Double) -> Path {
        let clamped = min(50, max(-50, cents))
        let deg = (clamped / 50) * maxDeg
        let rad = deg * Double.pi / 180
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy))
        path.addLine(to: CGPoint(
            x: cx + length * sin(rad),
            y: cy - length * cos(rad)
        ))
        return path
    }

    private static func tailPath(cents: Double) -> Path {
        let clamped = min(50, max(-50, cents))
        let deg = (clamped / 50) * maxDeg
        let rad = deg * Double.pi / 180
        let length = r * 0.16
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy))
        path.addLine(to: CGPoint(
            x: cx - length * sin(rad),
            y: cy + length * cos(rad)
        ))
        return path
    }

    // MARK: - 繪製（母本 paintGauge 順序：band→devArc→ticks→trail2→trail1→ghost→needle）

    private func drawGauge(in ctx: inout GraphicsContext) {
        let tol = tolerance
        let clamped = min(50, max(-50, cents))

        // 容差帶。
        ctx.stroke(
            Self.arcPath(c0: -tol, c1: tol, radius: Self.r - 1),
            with: .color(theme.ok.opacity(micActive ? 0.5 : 0.3)),
            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
        )

        // 偏差弧。
        if micActive && abs(clamped) > 0.6 {
            let color = inTune ? theme.ok : (clamped > 0 ? theme.sharp : theme.accent)
            ctx.stroke(
                Self.arcPath(c0: min(0, clamped), c1: max(0, clamped), radius: Self.r - 1),
                with: .color(color.opacity(inTune ? 0.75 : 0.52)),
                style: StrokeStyle(lineWidth: 4.2, lineCap: .round)
            )
        }

        // 刻度（−50…+50、步進 2）。
        for c in stride(from: -50.0, through: 50.0, by: 2.0) {
            let isMajor = c.truncatingRemainder(dividingBy: 10) == 0
            let inner = Self.r - (c == 0 ? 15 : isMajor ? 10 : 5)
            var line = Path()
            line.move(to: Self.point(cents: c, radius: inner))
            line.addLine(to: Self.point(cents: c, radius: Self.r))
            ctx.stroke(
                line,
                with: .color(abs(c) <= tol ? theme.ok : theme.textMuted),
                style: StrokeStyle(lineWidth: c == 0 ? 2.8 : isMajor ? 1.7 : 1.0)
            )
        }

        // 0 位冠標（母本 polygon 三點原值）。
        var crown = Path()
        crown.move(to: CGPoint(x: Self.cx, y: Self.cy - Self.r - 3.2))
        crown.addLine(to: CGPoint(x: Self.cx - 3.6, y: Self.cy - Self.r - 9.2))
        crown.addLine(to: CGPoint(x: Self.cx + 3.6, y: Self.cy - Self.r - 9.2))
        crown.closeSubpath()
        ctx.fill(crown, with: .color(theme.ok))

        // 尾跡與定格針（針下層）。
        let trailColor = inTune ? theme.ok : theme.accent
        if micActive {
            ctx.stroke(
                Self.armPath(cents: trail2Cents, length: Self.r - 3),
                with: .color(trailColor.opacity(0.07)),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
            )
            ctx.stroke(
                Self.armPath(cents: trail1Cents, length: Self.r - 3),
                with: .color(trailColor.opacity(0.15)),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
            )
        }
        if let ghost = ghostCents, ghostOpacity > 0 {
            ctx.stroke(
                Self.armPath(cents: ghost, length: Self.r - 3),
                with: .color(trailColor.opacity(ghostOpacity)),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
            )
        }

        // 主針：尾 → 臂 → 轂。
        ctx.stroke(
            Self.tailPath(cents: clamped),
            with: .color(theme.needle.opacity(0.45)),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
        )
        let armColor = inTune ? theme.ok : (micActive ? theme.accent : theme.needle)
        ctx.stroke(
            Self.armPath(cents: clamped, length: Self.r - 3),
            with: .color(armColor),
            style: StrokeStyle(lineWidth: 2.8, lineCap: .round)
        )
        let hubColor = inTune ? theme.ok : theme.needle
        ctx.fill(
            Path(ellipseIn: CGRect(
                x: Self.cx - 5, y: Self.cy - 5, width: 10, height: 10)),
            with: .color(hubColor)
        )
    }
}
