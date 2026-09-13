import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct RenderAssets {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let renderer = ImageRenderer(content: SampleScene(showsTitle: false)
            .frame(width: 896, height: 896)
            .clipShape(RoundedRectangle(cornerRadius: 200, style: .continuous))
            .frame(width: 1024, height: 1024))
        guard let image = renderer.cgImage else { fatalError("Could not render icon") }
        let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: "Assets/icon.png") as CFURL,
            UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
    }
}
