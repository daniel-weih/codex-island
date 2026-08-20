import AppKit

@MainActor
enum IslandScreenshotService {
    static func copyPNG(
        from view: NSView,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0,
              bounds.height > 0,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return false
        }

        view.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }

        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = bitmap.representation(using: .tiff, properties: [:]) {
            item.setData(tiff, forType: .tiff)
        }

        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
