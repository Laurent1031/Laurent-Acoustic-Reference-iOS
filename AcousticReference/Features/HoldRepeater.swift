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

    func pressBegan(action: @escaping () -> Void) {
        guard task == nil else { return }
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
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in repeater.pressBegan(action: action) }
                    .onEnded { _ in repeater.pressEnded(action: action) }
            )
    }
}
