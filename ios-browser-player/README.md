# Stream Browser iOS

Application iOS native en SwiftUI qui permet de :

- rechercher sur le web ou ouvrir une adresse `http://` / `https://` ;
- ouvrir les pages dans un navigateur intégré ;
- coller un lien HLS direct qui se termine par `.m3u8` ;
- lire le flux avec `AVPlayer` et mémoriser un historique local au format JSON.

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

Dans Xcode, remplacez `com.example.StreamBrowser` par votre propre identifiant de
bundle et sélectionnez votre équipe Apple. Si vous changez cet identifiant, mettez
également à jour la clé correspondante dans `ci/ExportOptions.plist`.

## Compiler une IPA avec GitHub Actions

Le workflow `../.github/workflows/ios.yml` compile automatiquement une vérification
pour le simulateur à chaque push. Pour créer une IPA signée, lancez manuellement
le workflow avec **Run workflow** dans GitHub.

Ajoutez ces secrets GitHub au dépôt :

| Secret | Valeur |
| --- | --- |
| `APPLE_TEAM_ID` | Team ID Apple Developer |
| `APPLE_CERTIFICATE_BASE64` | certificat `.p12` encodé en base64 |
| `APPLE_CERTIFICATE_PASSWORD` | mot de passe du `.p12` |
| `APPLE_PROVISIONING_PROFILE_BASE64` | profil `.mobileprovision` encodé en base64 |
| `APPLE_KEYCHAIN_PASSWORD` | mot de passe temporaire pour le trousseau CI |

Pour encoder les fichiers sans afficher leur contenu :

```bash
base64 -i distribution.p12 | pbcopy
base64 -i StreamBrowser.mobileprovision | pbcopy
```

Le profil de provisioning doit correspondre à l’identifiant de bundle utilisé dans
`project.yml`, et le certificat doit être un certificat **Apple Distribution**.
Une IPA signée avec un profil Ad Hoc est installable uniquement sur les appareils
autorisés par Apple. Pour TestFlight, adaptez `method` dans
`ci/ExportOptions.plist` à `app-store`.

## Remarque réseau

Le navigateur autorise les URLs HTTP et HTTPS afin de se comporter comme un navigateur
généraliste. Utilisez uniquement des contenus auxquels vous avez légalement accès.