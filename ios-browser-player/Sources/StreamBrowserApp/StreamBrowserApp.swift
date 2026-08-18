import SwiftUI
import UIKit

@MainActor
final class StreamBrowserAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            OfflineStore.shared?.handleBackgroundEvents(
                for: identifier,
                completionHandler: completionHandler
            )
        }
    }
}

@main
struct StreamBrowserApp: App {
    @UIApplicationDelegateAdaptor(StreamBrowserAppDelegate.self)
    private var appDelegate

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