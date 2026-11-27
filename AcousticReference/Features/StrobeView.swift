import SwiftUI

/// 頻閃主顯示（頻閃主模式段，Laurent 2026-11-26 定版：頻閃為
/// 預設主模式、錶盤指針退為輔助）。與 GaugeView 共用 320×190
/// 設計坐標與等比映射（正圓不變形），佔用同一顯示區高度預算。
///
/// 圖案：同心三環分段盤（外 36 段／中 24 段／內 12 段，佔空比
/// 0.52），三環同角旋轉——比照機械頻閃盤（一只盤面上多圈刻紋
/// 同步轉動）；多環不對應不同泛音，只提供盤面質感與不同半徑
/// 的運動參照（單一基頻相位驅動，避免多泛音相位互相打架）。
/// 頂部固定冠標（同 GaugeView 0 位冠標）作靜止參照，中心轂點。
///
/// 旋轉：相位錨點（phase／time）由 StrobePhaseTracker 以分析
/// 幀率（≈94 Hz）給出；本 View 以 TimelineView(.animation)
/// 在每顯示幀以 angularRate 外推（elapsed 鉗 0.5 s 防背景
/// 回歸跳變），ProMotion 120 Hz 下運動連續。無訊號或已靜止
/// 時 paused（凍結圖案、不耗電）。
///
/// 方向約定：patternPhase 遞增（偏高）→ 旋轉角為正 → 本坐標系
/// （y 向下）正角為視覺順時針，即偏高順時針、偏低逆時針。
/// rotationSign 是唯一符號開關：裝機實測若方向相反，只改此
/// 常數（追蹤器與數據鏈不動）。
///
/// 可信度渲染：亮段不透明度 = 0.30＋0.70×confidence、底帶
/// 0.10＋0.06×confidence（麥克風未開再 ×0.7）；無持續音時
/// 追蹤器凍結相位並衰減可信度，圖案自然靜止淡化，不亂轉。
/// 準音時亮段轉 ok 色（與錶盤針色邏輯一致），其餘 accent。
struct StrobeView: View {
    /// 相位錨點（弧度，於 anchorDate 時刻）。
    let phase: Double
    /// 角速度（弧度／秒，帶符號）。
    let rate: Double
    /// 相位錨點的牆鐘時刻（ViewModel 自分析 uptime 換算）。
    let anchorDate: Date
    /// 可信度 0…1。
    let confidence: Double
    let micActive: Bool
    let inTune: Bool
    let theme: TunerTheme

    /// 旋轉符號開關（見類註解）：+1 = 偏高順時針。
    private static let rotationSign: Double = 1

    // 盤面幾何（設計坐標 320×190）：中心 (160, 100)、外環
    // 半徑 84（頂 16、底 184，冠標佔 7–13，不重疊）。
    private static let cx: Double = 160
    private static let cy: Double = 100
    private static let rings: [(radius: Double, thickness: Double, segments: Int)] = [
        (84, 14, 36),
        (62, 12, 24),
        (40, 10, 12),
    ]
    private static let duty: Double = 0.52

    /// 圖案已靜止 → 暫停 TimelineView；麥克風未開恆暫停。
    /// 【返修批7・F4】舊條件要求 confidence 落底才暫停：準音
    /// 持續音時相位恆定（rate ≈ 0）但 confidence 恆高，盤面
    /// 以 120fps 全量重繪同一圖案（~500 次三角函數/幀白耗）。
    /// 改以 rate 為唯一判準（不論 confidence）：|rate| ≤ 0.02
    /// 時外推相位在 0.5 s 鉗制內位移 ≤ 0.01 rad，視覺靜止，
    /// 停繪無差異。
    private var isSettled: Bool {
        !micActive || abs(rate) <= 0.02
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: isSettled)) { context in
            Canvas { ctx, size in
                var ctx = ctx
                let elapsed = min(0.5, max(0, context.date.timeIntervalSince(anchorDate)))
                let displayPhase = phase + rate * elapsed
                draw(in: &ctx, size: size, phase: displayPhase * Self.rotationSign)
            }
        }
        .aspectRatio(320.0 / 190.0, contentMode: .fit)
    }

    // MARK: - 繪製

    private func draw(in ctx: inout GraphicsContext, size: CGSize, phase: Double) {
        let s = min(size.width / 320, size.height / 190)
        let ox = (size.width - 320 * s) / 2
        let oy = (size.height - 190 * s) / 2
        var ctx = ctx
        ctx.translateBy(x: ox, y: oy)
        ctx.scaleBy(x: s, y: s)

        let center = CGPoint(x: Self.cx, y: Self.cy)
        let dim = micActive ? 1.0 : 0.7
        let bandOpacity = dim * (0.10 + 0.06 * confidence)
        let litOpacity = dim * (0.30 + 0.70 * confidence)
        let litColor = inTune ? theme.ok : theme.accent

        for ring in Self.rings {
            // 底帶（整環，muted 低透明）——未亮段的盤面質地。
            var band = Path()
            let rOut = ring.radius + ring.thickness / 2
            let rIn = ring.radius - ring.thickness / 2
            band.addEllipse(in: CGRect(
                x: Self.cx - rOut, y: Self.cy - rOut,
                width: 2 * rOut, height: 2 * rOut))
            band.addEllipse(in: CGRect(
                x: Self.cx - rIn, y: Self.cy - rIn,
                width: 2 * rIn, height: 2 * rIn))
            ctx.fill(band, with: .color(theme.textMuted.opacity(bandOpacity)),
                     style: FillStyle(eoFill: true))

            // 亮段（偶數段，隨相位旋轉）。
            ctx.fill(
                Self.litSectorsPath(center: center, ring: ring, phase: phase),
                with: .color(litColor.opacity(litOpacity)))
        }

        // 頂部冠標（靜止參照，形制同 GaugeView 0 位冠標）。
        var crown = Path()
        crown.move(to: CGPoint(x: Self.cx, y: 13))
        crown.addLine(to: CGPoint(x: Self.cx - 3.6, y: 7))
        crown.addLine(to: CGPoint(x: Self.cx + 3.6, y: 7))
        crown.closeSubpath()
        ctx.fill(crown, with: .color(theme.ok))

        // 中心轂（同 GaugeView 轂色邏輯）。
        ctx.fill(
            Path(ellipseIn: CGRect(
                x: Self.cx - 5, y: Self.cy - 5, width: 10, height: 10)),
            with: .color(inTune ? theme.ok : theme.needle))
    }

    /// 一環的全部亮段（偶數索引段）合成單一路徑：每段以 ≤3°
    /// 步進取樣外弧→內弧折線（與 GaugeView arcPath 同法，
    /// 避免 addArc 方向語義歧義）。
    private static func litSectorsPath(
        center: CGPoint,
        ring: (radius: Double, thickness: Double, segments: Int),
        phase: Double
    ) -> Path {
        var path = Path()
        let step = 2 * Double.pi / Double(ring.segments)
        let rOut = ring.radius + ring.thickness / 2
        let rIn = ring.radius - ring.thickness / 2
        for i in stride(from: 0, to: ring.segments, by: 2) {
            let a0 = phase + Double(i) * step
            let a1 = a0 + step * duty
            let samples = max(2, Int(ceil((a1 - a0) / (Double.pi / 60))))
            for j in 0...samples {
                let a = a0 + (a1 - a0) * Double(j) / Double(samples)
                let p = CGPoint(
                    x: center.x + rOut * cos(a), y: center.y + rOut * sin(a))
                if j == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            for j in stride(from: samples, through: 0, by: -1) {
                let a = a0 + (a1 - a0) * Double(j) / Double(samples)
                path.addLine(to: CGPoint(
                    x: center.x + rIn * cos(a), y: center.y + rIn * sin(a)))
            }
            path.closeSubpath()
        }
        return path
    }
}
