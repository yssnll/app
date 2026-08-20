import SwiftUI
import WebKit

struct BrowserView: UIViewRepresentable {
    let url: URL?
    let onNavigate: (URL) -> Void
    let onLinkLongPress: (URL) -> Void
    let onVideoURL: (URL) -> Void
    let onOpenNewTab: (URL) -> Void

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
        if let url {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLinkLongPress = onLinkLongPress
        context.coordinator.onVideoURL = onVideoURL
        context.coordinator.onOpenNewTab = onOpenNewTab
        context.coordinator.onNavigate = onNavigate
        guard let url, webView.url?.absoluteString != url.absoluteString else { return }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLinkLongPress: onLinkLongPress,
            onVideoURL: onVideoURL,
            onOpenNewTab: onOpenNewTab,
            onNavigate: onNavigate
        )
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        var onLinkLongPress: (URL) -> Void
        var onVideoURL: (URL) -> Void
        var onOpenNewTab: (URL) -> Void
        var onNavigate: (URL) -> Void

        init(
            onLinkLongPress: @escaping (URL) -> Void,
            onVideoURL: @escaping (URL) -> Void,
            onOpenNewTab: @escaping (URL) -> Void,
            onNavigate: @escaping (URL) -> Void
        ) {
            self.onLinkLongPress = onLinkLongPress
            self.onVideoURL = onVideoURL
            self.onOpenNewTab = onOpenNewTab
            self.onNavigate = onNavigate
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url {
                onNavigate(url)
            }
        }

        func webView(
            _ webView: WKWebView,
            contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
            completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
        ) {
            if let linkURL = elementInfo.linkURL {
                let configuration = UIContextMenuConfiguration(
                    identifier: nil,
                    previewProvider: nil
                ) { _ in
                    let openAction = UIAction(
                        title: "Ouvrir dans un nouvel onglet",
                        image: UIImage(systemName: "plus.square.on.square")
                    ) { [weak self] _ in
                        self?.onOpenNewTab(linkURL)
                    }
                    let downloadAction = UIAction(
                        title: "Télécharger le lien",
                        image: UIImage(systemName: "arrow.down.circle")
                    ) { [weak self] _ in
                        self?.onLinkLongPress(linkURL)
                    }
                    return UIMenu(title: "", children: [openAction, downloadAction])
                }
                completionHandler(configuration)
                return
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
                } else if navigationAction.navigationType == .linkActivated {
                    onOpenNewTab(destinationURL)
                } else {
                    // Les popups publicitaires de Anime-Sama sont ouverts par
                    // un script (navigationType == .other). Ils ne doivent
                    // pas devenir des onglets de l'application.
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
            if let destinationURL = navigationAction.request.url {
                if Self.isVideoURL(destinationURL) {
                    onVideoURL(destinationURL)
                } else if navigationAction.navigationType == .linkActivated {
                    onOpenNewTab(destinationURL)
                }
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

        // Anime-Sama utilise aussi window.open() pour ses boutons de navigation.
        // On laisse passer les ouvertures utiles et on bloque uniquement les régies.
        try {
            const originalWindowOpen = window.open.bind(window);
            window.open = function(url, target, features) {
                const value = String(url || '');
                if (isBlockedAd(value)) return null;
                if (value && isVideo(value)) {
                    window.location.href = new URL(value, document.baseURI).href;
                    return null;
                }
                const destination = new URL(value || 'about:blank', document.baseURI).href;
                const requestedTarget = String(target || '_blank').toLowerCase();

                // Anime-Sama utilise window.open(url, '_self') pour ses
                // boutons internes. Une navigation explicite évite que
                // WKWebView la classe comme une popup scriptée et l'annule.
                if (requestedTarget === '_self'
                    || requestedTarget === '_parent'
                    || requestedTarget === '_top') {
                    window.location.href = destination;
                    return null;
                }

                // Les ouvertures _blank provenant de scripts sont les
                // popups publicitaires. Les vrais liens _blank passent par
                // la navigation native après un clic utilisateur.
                return null;
            };
        } catch (_) {}

        function isBlockedAd(value) {
            return /profitablecpmratenetwork|endlesshandbaglinked|d1zhmd1pxxxajf|d1pk6uu6wqrpce/i.test(String(value || ''));
        }

        // Les liens réels target=_blank doivent pouvoir atteindre le delegate natif.
        // On neutralise seulement les placeholders publicitaires (#) et les régies connues.
        document.addEventListener('click', (event) => {
            const element = event.target && event.target.closest
                ? event.target.closest('a[target="_blank"], area[target="_blank"]')
                : null;
            if (!element) return;
            const href = element.href || element.getAttribute('href') || '';
            if (!href || href === '#' || isBlockedAd(href)) event.preventDefault();
        }, true);
    })();
    """
}