import SwiftUI

@main
struct StreamBrowserApp: App {
    @StateObject private var browserStore = BrowserStore()
    @StateObject private var offlineStore = OfflineStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(browserStore)
                .environmentObject(offlineStore)
        }
    }
}