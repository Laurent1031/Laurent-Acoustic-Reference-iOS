import UIKit

/// 方向鎖管理器（階段 6，橫屏鐵律的執行點）：
///
/// - Info.plist 的 UISupportedInterfaceOrientations 宣告三向
///   （豎屏＋左右橫屏）只是「能力」，實際鎖定由 AppDelegate 的
///   application(_:supportedInterfaceOrientationsFor:) 回傳
///   本管理器的 mask 決定——預設恆為 .portrait，全 App 鎖豎屏。
/// - 唯一把 mask 改為 .landscape 的路徑是沉浸調音
///   （ImmersiveTunerView.onAppear），唯一改回 .portrait 的
///   路徑是其 onDisappear（fullScreenCover 的任何關閉路徑都
///   必經 onDisappear：點退出鈕、深連結切頁強制關閉、視圖
///   卸載）；App 被殺後重啟 mask 回預設 .portrait，不存在
///   「卡在橫屏」的持久狀態。
/// - 節拍器與其他全部頁面不觸碰本管理器，恆豎屏。
final class OrientationManager: @unchecked Sendable {
    static let shared = OrientationManager()

    private let lock = NSLock()
    private var _mask: UIInterfaceOrientationMask = .portrait

    /// AppDelegate 讀取（UIKit 主線程回調）。
    var mask: UIInterfaceOrientationMask {
        lock.lock()
        defer { lock.unlock() }
        return _mask
    }

    /// 設定鎖定並請求系統旋轉至目標方向：先更新 mask（delegate
    /// 下一次查詢即回新值）、通知根 VC 重算支援方向、再以
    /// requestGeometryUpdate 請求旋轉（iOS 16+ 正規路徑）。
    @MainActor
    func apply(_ newMask: UIInterfaceOrientationMask) {
        lock.lock()
        _mask = newMask
        lock.unlock()
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        else { return }
        scene.windows.first?.rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in
            // 請求被系統拒絕（例如裝置方向鎖）時不重試：mask
            // 已更新，裝置解鎖旋轉後系統會自行落位。
        }
    }
}
