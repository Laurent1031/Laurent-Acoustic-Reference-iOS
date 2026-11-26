import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            Text("LAURENT")
                .font(.system(size: 34, weight: .bold, design: .default))
                .tracking(10)
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    ContentView()
}
