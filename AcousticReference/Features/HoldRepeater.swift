import SwiftUI

/// 長按連調的時序協調（母本 addHoldRepeat，行 12170）：按下
/// 340 ms 後首發、其後每 62 ms 一次；340 ms 內抬手 → 由
/// pressEnded 補發一次普通點按（母本結尾 click 被吞、僅補單次
/// 的語義）。與 MetronomeView 內的私有 HoldRepeater 同式，供
/// A4 步進鈕使用（節拍器側的既有實現不動，避免階段 3 回歸）。
@MainActor
final class HoldRepeatController: ObservableObject {
    private var task: Task<Void, Never>?
    private var fired = false
    /// 按壓中（供 label 亮斑回饋，母本 .glass-press）。
    @Published private(set) var isPressing = false

    func pressBegan(action: @escaping () -> Void) {
        guard task == nil else { return }
        isPressing = true
        fired = false
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 340_000_000)
                self?.fired = true
                action()
                while true {
                    try await Task.sleep(nanoseconds: 62_000_000)
                    action()
                }
            } catch {
                // 已取消（手指抬起）：結束連調。
            }
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
