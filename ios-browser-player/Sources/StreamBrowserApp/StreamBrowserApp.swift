import SwiftUI

@main
struct StreamBrowserApp: App {
    @StateObject private var browserStore = BrowserStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(browserStore)
        }
    }
}