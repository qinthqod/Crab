import AppKit

enum MenuBarLogoIcon {
    static let image: NSImage = {
        guard
            let url = Bundle.main.url(forResource: "crab-protective-orbit", withExtension: "png"),
            let source = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Crab") ?? NSImage()
        }

        source.size = NSSize(width: 18, height: 18)
        let image = source.copy() as? NSImage ?? source
        image.isTemplate = true
        return image
    }()
}
