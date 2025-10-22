#!/bin/bash

echo "🧪 Running NowPlaying Tests..."

# Create a temporary test package
TEST_DIR="Tests"
TEMP_PACKAGE_DIR="TestPackage"

# Clean up any previous test runs
rm -rf "$TEMP_PACKAGE_DIR"

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

# Run tests
cd "$TEMP_PACKAGE_DIR"
echo "📦 Building test package..."
swift build

echo "🚀 Running tests..."
swift test

# Clean up
cd ..
rm -rf "$TEMP_PACKAGE_DIR"

echo "✅ Tests completed!"