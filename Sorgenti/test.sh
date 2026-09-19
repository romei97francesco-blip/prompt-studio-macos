#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
cache_dir="${TMPDIR:-/private/tmp}/promptstudio-test-module-cache"
binary="${TMPDIR:-/private/tmp}/PromptStudioRouterTests"

swiftc -module-cache-path "$cache_dir" OpenRouter.swift Test/RouterTests.swift -o "$binary"
"$binary"

