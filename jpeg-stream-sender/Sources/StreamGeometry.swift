import CoreGraphics
import Foundation

// Quartz screenshots and CGEvent locations both use the top-left screen origin.
enum StreamGeometry {
    static func rect(cursor: CGPoint, display: CGRect, frame: CGSize, zoom: CGFloat) -> CGRect {
        let z = max(1, zoom)
        let width = min(display.width, max(1, frame.width / z))
        let height = min(display.height, max(1, frame.height / z))
        return CGRect(x: min(max(cursor.x - width / 2, display.minX), display.maxX - width),
                      y: min(max(cursor.y - height / 2, display.minY), display.maxY - height),
                      width: width, height: height)
    }

    static func display(containing cursor: CGPoint) -> CGRect {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        if CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success {
            for id in ids.prefix(Int(count)) {
                let box = CGDisplayBounds(id)
                if box.contains(cursor) { return box }
            }
        }
        return CGDisplayBounds(CGMainDisplayID())
    }

    static func normalizedCursor(_ cursor: CGPoint, rect: CGRect) -> (CGFloat, CGFloat) {
        let x = min(1, max(0, (cursor.x - rect.minX) / rect.width))
        let y = min(1, max(0, (cursor.y - rect.minY) / rect.height))
        return (x, y)
    }

    static func selfTest() -> Bool {
        let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let cursor = CGPoint(x: -1919, y: 1)
        let crop = rect(cursor: cursor, display: display,
                        frame: CGSize(width: 640, height: 360), zoom: 4)
        let p = normalizedCursor(cursor, rect: crop)
        let center = rect(cursor: CGPoint(x: -1000, y: 400), display: display,
                          frame: CGSize(width: 640, height: 360), zoom: 4)
        return crop.minX == -1920 && crop.minY == 0
            && crop.width == 160 && crop.height == 90
            && p.0 > 0 && p.0 < 0.1 && p.1 > 0 && p.1 < 0.1
            && center.midX == -1000 && center.midY == 400
    }
}
