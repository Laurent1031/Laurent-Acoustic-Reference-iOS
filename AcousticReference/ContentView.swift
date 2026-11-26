import SwiftUI

struct ContentView: View {
    /// 全 App 共用一個音訊引擎實例：主畫面與診斷頁共用，
    /// 避免兩個引擎爭用音訊會話。
    @StateObject private var engine = AudioEngine()

    var body: some View {
        // 階段 2：錶盤主畫面（診斷頁自頂欄 sheet 喚出）。
        TunerView(engine: engine)
    }
}

#Preview {
    ContentView()
}
