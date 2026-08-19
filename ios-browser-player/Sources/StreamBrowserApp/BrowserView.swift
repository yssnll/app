import SwiftUI
import WebKit

struct BrowserView: UIViewRepresentable {
    let url: URL
    let onLinkLongPress: (URL) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLinkLongPress = onLinkLongPress
        guard webView.url?.absoluteString != url.absoluteString else { return }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkLongPress: onLinkLongPress)
    }

    final class Coordinator: NSObject, WKUIDelegate {
        var onLinkLongPress: (URL) -> Void

        init(onLinkLongPress: @escaping (URL) -> Void) {
            self.onLinkLongPress = onLinkLongPress
        }

        func webView(
            _ webView: WKWebView,
            contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
            completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
        ) {
            if let linkURL = elementInfo.linkURL {
                onLinkLongPress(linkURL)
            }
            completionHandler(nil)
        }
    }
}