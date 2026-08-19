import SwiftUI
import WebKit

struct BrowserView: UIViewRepresentable {
    let url: URL
    let onLinkLongPress: (URL) -> Void
    let onVideoURLDetected: (URL) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLinkLongPress = onLinkLongPress
        context.coordinator.onVideoURLDetected = onVideoURLDetected
        guard webView.url?.absoluteString != url.absoluteString else { return }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLinkLongPress: onLinkLongPress,
            onVideoURLDetected: onVideoURLDetected
        )
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        var onLinkLongPress: (URL) -> Void
        var onVideoURLDetected: (URL) -> Void

        init(
            onLinkLongPress: @escaping (URL) -> Void,
            onVideoURLDetected: @escaping (URL) -> Void
        ) {
            self.onLinkLongPress = onLinkLongPress
            self.onVideoURLDetected = onVideoURLDetected
        }

        // Advertising scripts commonly call window.open() after a tap.
        // Returning nil without loading the request suppresses that popup
        // while leaving the current page untouched.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let destinationURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if isVideoURL(destinationURL) {
                onVideoURLDetected(destinationURL)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if let responseURL = navigationResponse.response.url,
               isVideoURL(responseURL) {
                onVideoURLDetected(responseURL)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
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

        private func isVideoURL(_ url: URL) -> Bool {
            let lowercasedURL = url.absoluteString.lowercased()
            let pathExtension = url.pathExtension.lowercased()
            let extensions = ["m3u8", "mp4", "mov", "m4v", "webm"]
            return extensions.contains(pathExtension)
                || extensions.contains { lowercasedURL.contains(".\($0)") }
        }
    }
}