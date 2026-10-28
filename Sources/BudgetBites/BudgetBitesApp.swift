import SwiftUI

@main
struct BudgetBitesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(red: 246/255, green: 247/255, blue: 242/255)
                .ignoresSafeArea()
            WebViewContainer()
                .ignoresSafeArea()
        }
    }
}
