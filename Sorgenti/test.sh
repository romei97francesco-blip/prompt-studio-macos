#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
cache_dir="${TMPDIR:-/private/tmp}/promptstudio-test-module-cache"
binary="${TMPDIR:-/private/tmp}/PromptStudioRouterTests"

swiftc -module-cache-path "$cache_dir" OpenRouter.swift Test/RouterTests.swift -o "$binary"
"$binary"

keychain_binary="${TMPDIR:-/private/tmp}/PromptStudioKeychainTests"
swiftc -module-cache-path "$cache_dir" KeychainStore.swift Test/KeychainTests.swift -o "$keychain_binary" -framework Security
"$keychain_binary"
