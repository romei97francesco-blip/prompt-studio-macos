#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
version="1.1.3"
mkdir -p dist
./Sorgenti/test.sh
./Sorgenti/compila.sh
codesign --verify --verbose 'Prompt Studio.app'
plutil -lint 'Prompt Studio.app/Contents/Info.plist'
ditto -c -k --sequesterRsrc --keepParent 'Prompt Studio.app' "dist/Prompt-Studio-${version}-macOS.zip"
shasum -a 256 "dist/Prompt-Studio-${version}-macOS.zip" > "dist/Prompt-Studio-${version}-macOS.zip.sha256"

echo "Release pronta in dist/"
