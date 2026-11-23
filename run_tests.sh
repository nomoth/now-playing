#!/bin/bash
set -euo pipefail

echo "🧪 Running NowPlaying Tests..."

cd "$(dirname "$0")"

# Temporary SwiftPM package wrapping the sources, removed on exit even when a step fails
TEMP_PACKAGE_DIR="$PWD/TestPackage"
rm -rf "$TEMP_PACKAGE_DIR"
trap 'rm -rf "$TEMP_PACKAGE_DIR"' EXIT

# Create test package structure
mkdir -p "$TEMP_PACKAGE_DIR/Sources/NowPlaying"
mkdir -p "$TEMP_PACKAGE_DIR/Tests/NowPlayingTests"

# Copy source files (excluding main.swift since it makes it an executable)
cp AppDelegate.swift SpotifyMonitor.swift AppleScriptManager.swift AppConfig.swift "$TEMP_PACKAGE_DIR/Sources/NowPlaying/"

# Copy test files
cp Tests/*.swift "$TEMP_PACKAGE_DIR/Tests/NowPlayingTests/"

# Copy AppleScript files to Sources/NowPlaying (as resources)
cp Scripts/*.applescript "$TEMP_PACKAGE_DIR/Sources/NowPlaying/"

# Create Package.swift
cat > "$TEMP_PACKAGE_DIR/Package.swift" << 'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NowPlaying",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "NowPlaying",
            targets: ["NowPlaying"]),
    ],
    targets: [
        .target(
            name: "NowPlaying",
            resources: [
                .copy("spotify_state.applescript")
            ]),
        .testTarget(
            name: "NowPlayingTests",
            dependencies: ["NowPlaying"]),
    ]
)
EOF

echo "🚀 Building and running tests..."
# DECISION: SwiftPM runs with --disable-sandbox.
# The manifest is generated just above, so its sandbox protects nothing, and it cannot nest inside another sandbox (nono, CI).
swift test --disable-sandbox --package-path "$TEMP_PACKAGE_DIR"

echo "✅ Tests completed!"
