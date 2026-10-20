#!/bin/zsh
set -eu
SOURCE="${0:A:h}"
BUILD="$(mktemp -d -t homedeck-tests)"
trap 'rm -rf "$BUILD"' EXIT
cp "$SOURCE/test-main.swift.txt" "$BUILD/main.swift"
xcrun swiftc -swift-version 5 "$SOURCE/Cloud.swift" "$SOURCE/Devices.swift" "$SOURCE/Models.swift" "$BUILD/main.swift" -o "$BUILD/checks"
"$BUILD/checks"
