# Stream Browser iOS

Application iOS native en SwiftUI permettant de rechercher sur le web, d'ouvrir des
liens dans un navigateur intégré, de lire des flux vidéo HLS `.m3u8` et de conserver
des vidéos pour les regarder hors ligne.

## iOS & GitHub

- Le projet SwiftUI se trouve dans `ios-browser-player/`.
- `project.yml` est utilisé par XcodeGen pour générer `StreamBrowser.xcodeproj`.
- `.github/workflows/ios.yml` compile le simulateur à chaque push et génère une IPA
  non signée lors d'un lancement manuel, sans secrets Apple.
- Les instructions de certificat, provisioning profile et secrets GitHub sont dans
  `ios-browser-player/README.md`.

## Stack

- Swift 5, SwiftUI, WebKit, AVKit et FFmpegKit 6.0 via CocoaPods
- Déploiement cible : iOS 16+
- Configuration applicative : `Resources/app-config.json`
- Historique local : JSON via `Codable`

## Where things live

- `ios-browser-player/Sources/StreamBrowserApp/ContentView.swift` — navigation,
  recherche, navigateur et historique
- `ios-browser-player/Sources/StreamBrowserApp/BrowserView.swift` — navigateur web
  intégré avec `WKWebView` et détection de l'appui long sur les liens vidéo
- `ios-browser-player/Sources/StreamBrowserApp/HLSPlayerView.swift` — lecteur HLS
  avec `AVPlayer`, y compris les fichiers locaux
- `ios-browser-player/Sources/StreamBrowserApp/VideoQuality.swift` — lecture des
  playlists HLS et détection des qualités disponibles
- `ios-browser-player/Sources/StreamBrowserApp/OfflineStore.swift` — téléchargements
  locaux HLS/fichiers vidéo, conversion native en MP4 et persistance des vidéos hors ligne
- `ios-browser-player/ci/ExportOptions.plist` — options d'export de l'IPA

## Architecture decisions

- Les recherches sans URL sont envoyées vers DuckDuckGo.
- Les liens dont l'extension est `.m3u8` sont ouverts dans le lecteur AVPlayer.
- Un appui long sur un lien `.m3u8`, `.mp4`, `.mov`, `.m4v` ou `.webm` ouvre le
  choix de qualité avant le téléchargement.
- Les vidéos directes sont converties nativement en `.mp4`. Les playlists HLS
  MPEG-TS sont transcodées avec FFmpegKit en H.264/AAC dans un `.mp4` avant
  d’être marquées comme disponibles hors ligne. Les fichiers finaux sont
  exportables depuis le lecteur via la feuille de partage iOS.
- Les URLs temporaires ne sont pas stockées dans le code source : elles sont collées
  par l'utilisateur et peuvent apparaître dans l'historique local.
- L'IPA du workflow est volontairement non signée : elle sert à empaqueter le build,
  mais Apple exige une signature pour l'installation sur appareil.

## Product

Stream Browser offre une barre unique pour rechercher, naviguer et lancer des flux
HLS directs, avec historique local, partage du lien actif et bibliothèque « Hors
ligne » pour les vidéos téléchargées.

## User preferences

L'application doit pouvoir être compilée en IPA via GitHub Actions et servir de
navigateur de liens ainsi que de lecteur vidéo HLS.

## Gotchas

- Une IPA non signée n'est pas installable directement sur un iPhone ; un certificat
  Apple Distribution et un profil de provisioning seront nécessaires uniquement si
  une installation réelle ou TestFlight est demandé plus tard.
- Le lien HLS doit être valide, accessible et compatible avec AVPlayer ; les URLs
  signées avec une date d'expiration peuvent cesser de fonctionner.

## Pointers
- Voir `ios-browser-player/README.md` pour la génération Xcode et la configuration
  de GitHub Actions.
