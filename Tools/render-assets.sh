#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Assets build/AssetRenderer.app/Contents/{MacOS,Resources} build/ModuleCache
xcrun metal -c Sources/Fold.metal -o build/Fold.air
xcrun metallib build/Fold.air -o build/AssetRenderer.app/Contents/Resources/default.metallib
xcrun swiftc -swift-version 6 -O -D ASSET_RENDERER -parse-as-library \
    -module-cache-path build/ModuleCache Sources/*.swift Tools/RenderAssets.swift \
    -o build/AssetRenderer.app/Contents/MacOS/AssetRenderer \
    -framework AppKit -framework SwiftUI -framework ScreenCaptureKit -framework IOKit
build/AssetRenderer.app/Contents/MacOS/AssetRenderer
mkdir -p build/ClamShell.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/icon.png --out "build/ClamShell.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" Assets/icon.png --out "build/ClamShell.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/ClamShell.iconset -o Assets/ClamShell.icns
