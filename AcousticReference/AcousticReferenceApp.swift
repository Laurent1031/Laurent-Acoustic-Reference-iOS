import SwiftUI
import UIKit

/// 方向鎖的 UIKit 入口（階段 6）：支援方向一律回
/// OrientationManager 的現行 mask（預設 .portrait 全 App
/// 鎖豎屏；沉浸調音期間暫為 .landscape，退出即還原）。
/// Info.plist 宣告三向只是能力上限，實際鎖定以此為準。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationManager.shared.mask
    }
}

@main
struct AcousticReferenceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
