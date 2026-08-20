import AppKit
import Foundation

private final class RoundedFixtureView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 2, dy: 2),
            xRadius: 14,
            yRadius: 14
        ).fill()
    }
}

@main
struct ScreenshotChecks {
    @MainActor
    static func main() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name(
                "com.codex-island.screenshot-checks.\(UUID().uuidString)"
            )
        )
        defer { pasteboard.releaseGlobally() }

        let view = RoundedFixtureView(
            frame: NSRect(x: 0, y: 0, width: 120, height: 72)
        )
        view.displayIfNeeded()

        guard IslandScreenshotService.copyPNG(from: view, to: pasteboard),
              let png = pasteboard.data(forType: .png),
              let bitmap = NSBitmapImageRep(data: png) else {
            fail("rounded screenshot is copied as PNG data")
        }

        guard bitmap.hasAlpha else {
            fail("PNG preserves an alpha channel")
        }

        let cornerAlpha = bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1
        let centerAlpha = bitmap.colorAt(
            x: bitmap.pixelsWide / 2,
            y: bitmap.pixelsHigh / 2
        )?.alphaComponent ?? 0
        guard cornerAlpha < 0.05 else {
            fail("rounded PNG corners remain transparent")
        }
        guard centerAlpha > 0.95 else {
            fail("rounded PNG content remains opaque")
        }

        print("All screenshot checks passed")
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
