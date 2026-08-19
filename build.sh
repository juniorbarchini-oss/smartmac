#!/bin/bash
set -e

echo "Compiling SmartMac SwiftUI App..."
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)
swiftc -sdk "$SDK_PATH" -target arm64-apple-macos14.0 -parse-as-library main.swift -o SmartMac -O

echo "Creating App Bundle structure..."
mkdir -p SmartMac.app/Contents/MacOS
mkdir -p SmartMac.app/Contents/Resources

cp SmartMac SmartMac.app/Contents/MacOS/SmartMac
cp Info.plist SmartMac.app/Contents/Info.plist

echo "Application built successfully at: $(pwd)/SmartMac.app"
