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
        configuration.userContentController.add(context.coordinator, name: "videoLongPress")

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

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        var onLinkLongPress: (URL) -> Void
        var onVideoURL: (URL) -> Void
        var onOpenNewTab: (URL) -> Void
        var onNavigate: (URL) -> Void
        private var detectedVideoURLs: Set<String> = []

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

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "videoLongPress",
                  let value = message.body as? String,
                  let url = URL(string: value),
                  Self.isPotentialVideoURL(url)
            else {
                return
            }

            let normalizedURL = url.absoluteString
            guard !detectedVideoURLs.contains(normalizedURL) else { return }
            detectedVideoURLs.insert(normalizedURL)
            onLinkLongPress(url)
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
                    detectedVideoURLs.insert(destinationURL.absoluteString)
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
                detectedVideoURLs.insert(destinationURL.absoluteString)
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
                detectedVideoURLs.insert(responseURL.absoluteString)
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
                }
            }

            // Les popups publicitaires scriptés sont bloqués. Le script
            // JavaScript fournit lui-même un objet temporaire à
            // window.open(), afin que le site comptabilise l'ouverture sans
            // changer l'onglet Anime-Sama ni afficher about:blank.
            return nil
        }

        private static func isVideoURL(_ url: URL) -> Bool {
            let videoExtensions = ["m3u8", "mp4", "mov", "m4v", "webm", "mkv", "avi"]
            return videoExtensions.contains(url.pathExtension.lowercased())
        }

        private static func isPotentialVideoURL(_ url: URL) -> Bool {
            if isVideoURL(url) {
                return true
            }
            let value = url.absoluteString.lowercased()
            return ["mpd", "ts", "m4s", "aac"].contains(url.pathExtension.lowercased())
                || value.contains("manifest")
                || value.contains("playlist")
                || value.contains("videoplayback")
                || value.contains("video_url")
                || value.contains("videourl")
                || value.contains("stream")
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
        // Sur un lecteur intégré, le lien de la page est celui de Anime-Sama,
        // pas le flux vidéo. Chercher dans plusieurs endroits rend la
        // récupération fiable avec les lecteurs qui masquent leur <video>.
        const isLikelyVideoURL = (value) => {
            if (typeof value !== 'string' || !value || /^(blob:|data:)/i.test(value)) {
                return false;
            }
            return /(?:\\.(m3u8|mpd|mp4|mov|m4v|webm|mkv|avi|ts|m4s|aac)(?:[?#]|$))/i.test(value)
                || /(?:manifest|master\\.m3u8|playlist|videoplayback|video_url|videoUrl|stream)/i.test(value)
                || /(?:[?&](?:mime|type|format)=video(?:%2F|\\/)|[?&](?:mime|type)=(?:application%2Fx-mpegurl|application\\/x-mpegurl))/i.test(value);
        };

        const sendVideoURL = (value) => {
            if (!isLikelyVideoURL(value)) return;
            try {
                const absoluteSource = new URL(value, document.baseURI).href;
                if (/^(blob:|data:)/i.test(absoluteSource)) return;
                window.webkit.messageHandlers.videoLongPress.postMessage(absoluteSource);
            } catch (_) {}
        };

        const findVideoSource = (target) => {
            const candidates = [];
            const video = target && target.closest ? target.closest('video') : null;
            if (video) {
                candidates.push(video.currentSrc, video.src);
            }

            document.querySelectorAll('video, video source, source').forEach((element) => {
                candidates.push(
                    element.currentSrc,
                    element.src,
                    element.getAttribute('src'),
                    element.getAttribute('data-src'),
                    element.getAttribute('data-video')
                );
            });

            try {
                performance.getEntriesByType('resource').forEach((entry) => {
                    candidates.push(entry.name);
                });
            } catch (_) {}

            return candidates
                .filter((value) => typeof value === 'string' && value.length > 0)
                .find(isLikelyVideoURL);
        };

        const sendVideoSource = (target) => {
            const source = findVideoSource(target);
            if (!source) return;
            try {
                sendVideoURL(source);
            } catch (_) {}
        };

        // Les lecteurs modernes chargent souvent le manifeste ou les segments
        // avec fetch/XHR : il n’existe alors aucun lien vidéo dans le DOM.
        try {
            const originalFetch = window.fetch;
            window.fetch = function(input, init) {
                const requestURL = typeof input === 'string' ? input : (input && input.url);
                return originalFetch.apply(this, arguments).then((response) => {
                    const contentType = response.headers && response.headers.get
                        ? (response.headers.get('content-type') || '') : '';
                    if (/^(video\\/|application\\/(?:vnd\\.apple\\.mpegurl|x-mpegurl|dash\\+xml))/i.test(contentType)
                        || isLikelyVideoURL(requestURL)) {
                        sendVideoURL(requestURL);
                    }
                    return response;
                });
            };
        } catch (_) {}

        try {
            const originalOpen = XMLHttpRequest.prototype.open;
            const originalSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method, requestURL) {
                this.__streamBrowserURL = requestURL;
                return originalOpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function() {
                this.addEventListener('load', () => {
                    const contentType = this.getResponseHeader('content-type') || '';
                    if (/^(video\\/|application\\/(?:vnd\\.apple\\.mpegurl|x-mpegurl|dash\\+xml))/i.test(contentType)
                        || isLikelyVideoURL(this.__streamBrowserURL)) {
                        sendVideoURL(this.__streamBrowserURL);
                    }
                });
                return originalSend.apply(this, arguments);
            };
        } catch (_) {}

        try {
            performance.getEntriesByType('resource').forEach((entry) => {
                if (isLikelyVideoURL(entry.name)) sendVideoURL(entry.name);
            });
        } catch (_) {}

        // Certains lecteurs injectent la vidéo et chargent sa source en
        // JavaScript sans déclencher de navigation ni de menu contextuel.
        const observeVideoElement = (video) => {
            if (!video || video.__streamBrowserObserved) return;
            video.__streamBrowserObserved = true;
            ['loadedmetadata', 'canplay', 'play'].forEach((eventName) => {
                video.addEventListener(eventName, () => sendVideoSource(video), {passive: true});
            });
            sendVideoSource(video);
        };

        const scanForVideos = () => {
            document.querySelectorAll('video').forEach(observeVideoElement);
            document.querySelectorAll('video source, source').forEach((source) => {
                const parent = source.closest ? source.closest('video') : null;
                if (parent) observeVideoElement(parent);
                else sendVideoSource(source);
            });
        };

        const installVideoObserver = () => {
            try {
                if (!document.documentElement) return;
                new MutationObserver(scanForVideos).observe(document.documentElement, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    attributeFilter: ['src', 'data-src', 'data-video']
                });
            } catch (_) {}
        };
        scanForVideos();
        installVideoObserver();
        document.addEventListener('DOMContentLoaded', () => {
            scanForVideos();
            installVideoObserver();
        }, true);

        let longPressTimer = null;
        const cancelVideoLongPress = () => {
            if (longPressTimer !== null) {
                clearTimeout(longPressTimer);
                longPressTimer = null;
            }
        };

        const startVideoLongPress = (event) => {
            cancelVideoLongPress();
            longPressTimer = setTimeout(() => {
                longPressTimer = null;
                sendVideoSource(event.target);
            }, 600);
        };

        document.addEventListener('contextmenu', (event) => {
            sendVideoSource(event.target);
        }, true);
        document.addEventListener('touchstart', startVideoLongPress, {capture: true, passive: true});
        document.addEventListener('touchend', cancelVideoLongPress, true);
        document.addEventListener('touchcancel', cancelVideoLongPress, true);
        document.addEventListener('pointerdown', startVideoLongPress, true);
        document.addEventListener('pointerup', cancelVideoLongPress, true);
        document.addEventListener('pointercancel', cancelVideoLongPress, true);

        const isVideo = (value) => {
            try {
                const url = new URL(value, document.baseURI);
             return /\\.(m3u8|mp4|mov|m4v|webm|mkv|avi)(?:$|[?#])/i.test(url.pathname + url.search);
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

                // Retourner un objet temporaire : Anime-Sama vérifie le
                // retour de window.open() avant de déverrouiller ses boutons.
                // Aucun onglet ni navigation native n'est créé.
                return {
                    closed: false,
                    close: function() { this.closed = true; }
                };
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