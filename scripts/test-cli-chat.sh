#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mati-notch-cli-chat.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  mati-notch/Sources/App/CLIChat.swift tests/CLIChatTests.swift \
  -o "$TEST_DIR/cli-chat-tests"
"$TEST_DIR/cli-chat-tests" "$@"
