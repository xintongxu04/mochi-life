import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Mochi Life")
                .font(.largeTitle)
                .bold()
            Text("Hello, Mochi.")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
