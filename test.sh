#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/ModuleCache
rtk proxy xcrun swiftc -swift-version 6 -module-cache-path build/ModuleCache \
    Sources/LidSensor.swift Sources/FoldMath.swift Tests/main.swift -o build/checks -framework IOKit
rtk proxy build/checks "$@"
rtk proxy xcrun swiftc -swift-version 6 -D CONTROLLER_CHECKS -parse-as-library \
    -module-cache-path build/ModuleCache Sources/*.swift Tests/controller.swift \
    -o build/controller-checks -framework AppKit -framework SwiftUI -framework ScreenCaptureKit -framework IOKit
rtk proxy build/controller-checks
