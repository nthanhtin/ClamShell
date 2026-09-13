#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
CLAMSHELL_SIGNING_IDENTITY=${CLAMSHELL_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2; exit}')}
if [[ -z "$CLAMSHELL_SIGNING_IDENTITY" ]]; then
    echo "Set CLAMSHELL_SIGNING_IDENTITY to a code-signing identity, or - for an ad hoc build." >&2
    exit 1
fi
mkdir -p build/ClamShell.app/Contents/{MacOS,Resources} build/ModuleCache
xcrun metal -target air64-apple-macos14.0 -c Sources/Fold.metal -o build/Fold.air
xcrun metallib build/Fold.air -o build/ClamShell.app/Contents/Resources/default.metallib
xcrun swiftc -swift-version 6 -O -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path build/ModuleCache Sources/*.swift \
    -o build/ClamShell.app/Contents/MacOS/ClamShell \
    -framework AppKit -framework SwiftUI -framework ScreenCaptureKit -framework IOKit
cp Info.plist build/ClamShell.app/Contents/Info.plist
cp Assets/ClamShell.icns build/ClamShell.app/Contents/Resources/ClamShell.icns
cp LICENSE build/ClamShell.app/Contents/Resources/LICENSE
codesign --force --sign "$CLAMSHELL_SIGNING_IDENTITY" build/ClamShell.app
codesign --verify --strict build/ClamShell.app
echo "Built: $PWD/build/ClamShell.app"
