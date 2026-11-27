import SwiftUI

/// 長按連調的時序協調（母本 addHoldRepeat，行 12170）：按下
/// 340 ms 後首發、其後每 62 ms 一次；340 ms 內抬手 → 由
/// pressEnded 補發一次普通點按（母本結尾 click 被吞、僅補單次
/// 的語義）。與 MetronomeView 內的私有 HoldRepeater 同式，供
/// A4 步進鈕使用（節拍器側的既有實現不動，避免階段 3 回歸）。
@MainActor
final class HoldRepeatController: ObservableObject {
    private var task: Task<Void, Never>?
    private var generation = 0
    private var fired = false
    /// 按壓中（供 label 亮斑回饋，母本 .glass-press）。
    @Published private(set) var isPressing = false

    func pressBegan(action: @escaping () -> Void) {
        guard task == nil else { return }
        isPressing = true
        fired = false
        generation += 1
        let gen = generation
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 340_000_000)
                // 【全邏輯複查・低】340 ms 邊界競態：sleep
                // 剛完成、續行未跑時 pressEnded 先行（已補
                // 發一次並 cancel），續行若不查取消狀態會
                // 再發一次（同按壓雙發一步）。睡醒先驗取消。
                guard !Task.isCancelled else { return }
                self?.fired = true
                action()
                // 【返修批2・按鍵審計】連調上限 500 發
                // （≈31 s）：pressing(false) 若因手勢取消
                // 未送達，連調不致無限持續。
                for _ in 0..<500 {
                    try await Task.sleep(nanoseconds: 62_000_000)
                    guard !Task.isCancelled else { return }
                    action()
                }
            } catch {
                // 已取消（手指抬起）：結束連調。
            }
            // 自然跑完時自清（審計修復）：完成路徑此前不清
            // task，若 pressing(false) 又未送達，pressBegan 的
            // guard 會令此鈕在 View 生命週期內永久無反應。
            // 以代次比對防誤清後繼按壓的 Task。
            if let self, self.generation == gen { self.task = nil }
        }
    }

    func pressEnded(action: () -> Void) {
        isPressing = false
        task?.cancel()
        task = nil
        if !fired { action() }
        fired = false
    }
}

/// 長按連調步進鈕（A4 列的 −／+）：外觀由呼叫端以 label 決定。
struct HoldRepeatButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @StateObject private var repeater = HoldRepeatController()

    var body: some View {
        label()
            .brightness(repeater.isPressing ? 0.10 : 0)
            .animation(.easeOut(duration: 0.25), value: repeater.isPressing)
            .contentShape(Rectangle())
            // 同 MetronomeHoldRepeatButton：系統長按識別器
            // pressing 回調驅動（DragGesture 版實機不觸發）。
            .onLongPressGesture(minimumDuration: 0.34, maximumDistance: 12,
                                pressing: { pressing in
                                    if pressing {
                                        repeater.pressBegan(action: action)
                                    } else {
                                        repeater.pressEnded(action: action)
                                    }
                                },
                                perform: {})
            .accessibilityAddTraits(.isButton)
    }
}
