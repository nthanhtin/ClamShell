#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Assets build/AssetRenderer.app/Contents/{MacOS,Resources} build/ModuleCache
rtk proxy xcrun metal -c Sources/Fold.metal -o build/Fold.air
rtk proxy xcrun metallib build/Fold.air -o build/AssetRenderer.app/Contents/Resources/default.metallib
rtk proxy xcrun swiftc -swift-version 6 -O -D ASSET_RENDERER -parse-as-library \
    -module-cache-path build/ModuleCache Sources/*.swift Tools/RenderAssets.swift \
    -o build/AssetRenderer.app/Contents/MacOS/AssetRenderer \
    -framework AppKit -framework SwiftUI -framework ScreenCaptureKit -framework IOKit
rtk proxy build/AssetRenderer.app/Contents/MacOS/AssetRenderer
mkdir -p build/ClamShell.iconset
for size in 16 32 128 256 512; do
    rtk proxy sips -z "$size" "$size" Assets/icon.png --out "build/ClamShell.iconset/icon_${size}x${size}.png" >/dev/null
    rtk proxy sips -z "$((size * 2))" "$((size * 2))" Assets/icon.png --out "build/ClamShell.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
rtk proxy iconutil -c icns build/ClamShell.iconset -o Assets/ClamShell.icns
