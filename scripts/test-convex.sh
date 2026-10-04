#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mati-notch-convex.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    mati-notch/Sources/App/ConvexClient.swift \
    mati-notch/Sources/App/ConvexStore.swift \
    tests/ConvexTests.swift -o "$TEST_DIR/convex-tests"
"$TEST_DIR/convex-tests"
