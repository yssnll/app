# Stream Browser iOS

Application iOS native en SwiftUI qui permet de :

- rechercher sur le web ou ouvrir une adresse `http://` / `https://` ;
- ouvrir les pages dans un navigateur intégré ;
- coller un lien HLS direct qui se termine par `.m3u8` ;
- lire le flux avec `AVPlayer` et mémoriser un historique local au format JSON.
- télécharger les vidéos directes en `.mp4` et les flux HLS en fichier vidéo
  local assemblé, lisible directement par `AVPlayer`.

Le lien HLS doit être collé dans la barre de navigation. Les liens temporaires ne sont
pas stockés dans le code source.

## Générer le projet Xcode

Le projet Xcode est généré à partir de `project.yml` avec
[XcodeGen](https://github.com/yonaskolb/XcodeGen) :

```bash
brew install xcodegen
cd ios-browser-player
xcodegen generate
open StreamBrowser.xcodeproj
```

Le projet utilise également FFmpegKit 6.0 via CocoaPods. Après
`xcodegen generate`, installez la dépendance avec :

```bash
pod install --repo-update
open StreamBrowser.xcworkspace
```

Il faut ouvrir le fichier `.xcworkspace`, et non plus le `.xcodeproj`. Les flux
HLS MPEG-TS sont transcodés en H.264/AAC dans un conteneur MP4 avant d'être
ajoutés à la bibliothèque hors ligne.

Dans Xcode, remplacez `com.example.StreamBrowser` par votre propre identifiant de
bundle et sélectionnez votre équipe Apple. Si vous changez cet identifiant, mettez
également à jour la clé correspondante dans `ci/ExportOptions.plist`.

## Compiler une IPA non signée avec GitHub Actions

Le workflow `../.github/workflows/ios.yml` compile automatiquement une vérification
pour le simulateur à chaque push. Pour créer une IPA non signée, lancez manuellement
le workflow avec **Run workflow** dans GitHub. Aucun secret Apple n'est nécessaire.

L'artefact produit s'appelle `StreamBrowser-unsigned-ipa`. Il contient bien un paquet
`.ipa`, mais il n'est pas installable directement sur un iPhone : Apple exige une
signature et un provisioning profile pour l'installation sur appareil ou pour
TestFlight. `ci/ExportOptions.plist` est conservé comme modèle pour une signature
ultérieure si nécessaire.

## Remarque réseau

Le navigateur autorise les URLs HTTP et HTTPS afin de se comporter comme un navigateur
généraliste. Utilisez uniquement des contenus auxquels vous avez légalement accès.