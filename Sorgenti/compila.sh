#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p '../Prompt Studio.app/Contents/MacOS' '../Prompt Studio.app/Contents/Resources'
cp Info.plist '../Prompt Studio.app/Contents/Info.plist'
cp PromptStudio.icns '../Prompt Studio.app/Contents/Resources/PromptStudio.icns'
module_cache="${TMPDIR:-/private/tmp}/promptstudio-module-cache"
swiftc -module-cache-path "$module_cache" -parse-as-library PromptStudio.swift OpenRouter.swift KeychainStore.swift -o '../Prompt Studio.app/Contents/MacOS/PromptStudio' -framework SwiftUI -framework AppKit -framework Security
codesign --force --sign - '../Prompt Studio.app'
