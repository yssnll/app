import SwiftUI
import WebKit

struct BrowserView: UIViewRepresentable {
    let url: URL
    let onLinkLongPress: (URL) -> Void
    let onVideoURL: (URL) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let popupBlocker = WKUserScript(
            source: Self.popupBlockerScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(popupBlocker)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLinkLongPress = onLinkLongPress
        context.coordinator.onVideoURL = onVideoURL
        guard webView.url?.absoluteString != url.absoluteString else { return }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLinkLongPress: onLinkLongPress,
            onVideoURL: onVideoURL
        )
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        var onLinkLongPress: (URL) -> Void
        var onVideoURL: (URL) -> Void

        init(
            onLinkLongPress: @escaping (URL) -> Void,
            onVideoURL: @escaping (URL) -> Void
        ) {
            self.onLinkLongPress = onLinkLongPress
            self.onVideoURL = onVideoURL
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

        // Les pubs du site utilisent généralement target="_blank" ou window.open.
        // Ne jamais créer une seconde WKWebView : cela évite que la pub bloque
        // l'interface, tout en laissant les vrais liens vidéo aller au lecteur.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let destinationURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil {
                if Self.isVideoURL(destinationURL) {
                    onVideoURL(destinationURL)
                }
                decisionHandler(.cancel)
                return
            }

            if Self.isVideoURL(destinationURL) {
                onVideoURL(destinationURL)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if let responseURL = navigationResponse.response.url,
               Self.isVideoResponse(navigationResponse.response) {
                onVideoURL(responseURL)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        // Retourner nil bloque aussi les window.open qui arrivent sans
        // navigationAction exploitable, au lieu d'ouvrir une fenêtre publicitaire.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let destinationURL = navigationAction.request.url,
               Self.isVideoURL(destinationURL) {
                onVideoURL(destinationURL)
            }
            return nil
        }

        private static func isVideoURL(_ url: URL) -> Bool {
            let videoExtensions = ["m3u8", "mp4", "mov", "m4v", "webm"]
            return videoExtensions.contains(url.pathExtension.lowercased())
        }

        private static func isVideoResponse(_ response: URLResponse) -> Bool {
            guard let mimeType = response.mimeType?.lowercased() else { return false }
            return mimeType.contains("mpegurl")
                || mimeType.contains("mp4")
                || mimeType.hasPrefix("video/")
        }
    }

    private static let popupBlockerScript = """
    (() => {
        const isVideo = (value) => {
            try {
                const url = new URL(value, document.baseURI);
                return /\\.(m3u8|mp4|mov|m4v|webm)(?:$|[?#])/i.test(url.pathname + url.search);
            } catch (_) {
                return false;
            }
        };

        // Les régies utilisent window.open() pour ouvrir la publicité.
        // Retourner null laisse le code du bouton continuer sans créer d’onglet.
        try {
            window.open = function(url) {
                if (url && isVideo(url)) {
                    window.location.href = new URL(url, document.baseURI).href;
                }
                return null;
            };
        } catch (_) {}

        // Empêche uniquement la navigation par défaut des liens publicitaires
        // target=_blank. Les gestionnaires de clic du site restent exécutés.
        document.addEventListener('click', (event) => {
            const element = event.target && event.target.closest
                ? event.target.closest('a[target="_blank"], area[target="_blank"]')
                : null;
            if (!element) return;
            const href = element.href || element.getAttribute('href') || '';
            if (!isVideo(href)) event.preventDefault();
        }, true);
    })();
    """
}