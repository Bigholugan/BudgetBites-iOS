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
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Native background matches the HTML app's color scheme to avoid flashes
            (colorScheme == .dark
                ? Color(red: 17/255, green: 22/255, blue: 17/255)
                : Color(red: 246/255, green: 247/255, blue: 242/255))
                .ignoresSafeArea()
            WebViewContainer()
                .ignoresSafeArea()
        }
    }
}
