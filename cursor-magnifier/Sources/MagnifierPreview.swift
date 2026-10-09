import AppKit
import CoreGraphics
import ScreenCaptureKit
import Darwin

// CoreGraphics screen bounds and CGEvent cursor positions use Quartz coordinates.
enum CaptureGeometry {
    static func rect(around cursor: CGPoint, in display: CGRect,
                     preview: CGSize, zoom: CGFloat) -> CGRect {
        let width = min(display.width, max(1, preview.width / max(zoom, 1)))
        let height = min(display.height, max(1, preview.height / max(zoom, 1)))
        let x = min(max(cursor.x - width / 2, display.minX), display.maxX - width)
        let y = min(max(cursor.y - height / 2, display.minY), display.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func relativeCursor(_ cursor: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: (cursor.x - rect.minX) / rect.width,
                y: (cursor.y - rect.minY) / rect.height)
    }

    static func display(containing cursor: CGPoint) -> CGRect {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        if CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success {
            for id in ids.prefix(Int(count)) {
                let frame = CGDisplayBounds(id)
                if frame.contains(cursor) { return frame }
            }
        }
        return CGDisplayBounds(CGMainDisplayID())
    }

    // Quartz cursor fractions grow downward; the default AppKit view grows upward.
    static func appKitY(screenFraction: CGFloat, height: CGFloat) -> CGFloat {
        (1 - screenFraction) * height
    }

    static func selfTest() -> Bool {
        let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let center = rect(around: CGPoint(x: -1000, y: 400), in: display,
                          preview: CGSize(width: 400, height: 400), zoom: 4)
        let edge = rect(around: CGPoint(x: -1919, y: 1), in: display,
                        preview: CGSize(width: 400, height: 400), zoom: 4)
        let point = relativeCursor(CGPoint(x: -1919, y: 1), in: edge)
        return center.width == 100 && center.height == 100
            && center.midX == -1000 && center.midY == 400
            && edge.minX == display.minX && edge.minY == display.minY
            && point.x > 0 && point.x < 0.1 && point.y > 0 && point.y < 0.1
            && appKitY(screenFraction: 0.25, height: 100) == 75
            && appKitY(screenFraction: 0.75, height: 100) == 25
    }
}

@MainActor
final class MagnifierPreview: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var target = CGPoint(x: 0.5, y: 0.5) { didSet { needsDisplay = true } }
    // Do not flip the AppKit canvas: NSImage rendering is otherwise upside down.
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(rect: bounds).fill()
        if let image {
            NSGraphicsContext.current?.imageInterpolation = .none
            image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        } else {
            let message = "画面を取得するとここに表示します"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.lightGray
            ]
            let size = (message as NSString).size(withAttributes: attributes)
            (message as NSString).draw(
                at: CGPoint(x: (bounds.width - size.width) / 2,
                            y: (bounds.height - size.height) / 2),
                withAttributes: attributes
            )
        }
        let cx = target.x * bounds.width
        let cy = CaptureGeometry.appKitY(screenFraction: target.y, height: bounds.height)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: cx - 16, y: cy))
        path.line(to: CGPoint(x: cx - 5, y: cy))
        path.move(to: CGPoint(x: cx + 5, y: cy))
        path.line(to: CGPoint(x: cx + 16, y: cy))
        path.move(to: CGPoint(x: cx, y: cy - 16))
        path.line(to: CGPoint(x: cx, y: cy - 5))
        path.move(to: CGPoint(x: cx, y: cy + 5))
        path.line(to: CGPoint(x: cx, y: cy + 16))
        path.lineWidth = 2
        NSColor.black.withAlphaComponent(0.75).setStroke()
        path.stroke()
        path.lineWidth = 1
        NSColor.systemYellow.setStroke()
        path.stroke()
    }
}
