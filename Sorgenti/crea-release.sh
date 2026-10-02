#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Sorgenti/Info.plist)
mkdir -p dist
./Sorgenti/test.sh
./Sorgenti/compila.sh
codesign --verify --verbose 'Prompt Studio.app'
plutil -lint 'Prompt Studio.app/Contents/Info.plist'
ditto -c -k --sequesterRsrc --keepParent 'Prompt Studio.app' "dist/Prompt-Studio-${version}-macOS.zip"
shasum -a 256 "dist/Prompt-Studio-${version}-macOS.zip" > "dist/Prompt-Studio-${version}-macOS.zip.sha256"

# Nota sulla notarizzazione.
# La firma applicata da compila.sh è ad hoc (locale): l'app funziona sul Mac che
# l'ha compilata, ma non è notarizzata da Apple. La notarizzazione richiede un
# account Apple Developer a pagamento, un certificato "Developer ID Application"
# e credenziali (Apple ID con password per app oppure API key) che non devono
# essere salvate nel repository. Per questo lo script non la esegue.
#
# Passi manuali, da compiere solo con credenziali proprie e fuori da questo script:
#   1. firmare con il certificato Developer ID (codesign --sign "Developer ID Application: ..." --options runtime --timestamp)
#   2. xcrun notarytool submit "dist/Prompt-Studio-${version}-macOS.zip" --keychain-profile <profilo> --wait
#   3. xcrun stapler staple 'Prompt Studio.app'
#   4. ricreare lo zip e l'hash dopo la spillatura.

echo "Release pronta in dist/ (firmata localmente, non notarizzata)"
