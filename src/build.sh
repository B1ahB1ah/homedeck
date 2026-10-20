#!/bin/zsh
set -eu
SOURCE="${0:A:h}"
OUT="${SOURCE:h}/家控台分享版.app"
BUILD="$(mktemp -d -t homedeck-share)"
trap 'rm -rf "$BUILD"' EXIT
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
for ARCH in arm64 x86_64; do
    xcrun clang -target "$ARCH-apple-macos13.0" -fobjc-arc -c "$SOURCE/TouchBarBridge.m" -o "$BUILD/bridge-$ARCH.o"
    xcrun swiftc -target "$ARCH-apple-macos13.0" -swift-version 5 -O \
        -import-objc-header "$SOURCE/TouchBarBridge.h" \
        -framework AppKit -framework SwiftUI -framework ServiceManagement \
        "$SOURCE/Cloud.swift" "$SOURCE/Devices.swift" "$SOURCE/Models.swift" \
        "$SOURCE/Views.swift" "$SOURCE/Onboarding.swift" "$SOURCE/TouchBar.swift" "$SOURCE/main.swift" \
        "$BUILD/bridge-$ARCH.o" -o "$BUILD/HomeDeckShare-$ARCH"
done
xcrun lipo -create "$BUILD/HomeDeckShare-arm64" "$BUILD/HomeDeckShare-x86_64" -output "$OUT/Contents/MacOS/HomeDeckShare"
cp "$SOURCE/Info.plist" "$OUT/Contents/Info.plist"
cp "$SOURCE/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$OUT"
codesign --verify --deep --strict "$OUT"
echo "Built and verified: $OUT"
