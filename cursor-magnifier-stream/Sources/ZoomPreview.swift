import AppKit
import CoreGraphics
import Darwin

final class ZoomPreview: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var target = CGPoint(x: 0.5, y: 0.5) {
        didSet {
            if abs(target.x - oldValue.x) > 0.002 ||
               abs(target.y - oldValue.y) > 0.002 { needsDisplay = true }
        }
    }
    override var isFlipped: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(rect: bounds).fill()
        if let image {
            NSGraphicsContext.current?.imageInterpolation = .none
            image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        } else {
            let hint = "画面収録を許可すると、ここに拡大表示します"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.lightGray
            ]
            let sz = (hint as NSString).size(withAttributes: attributes)
            (hint as NSString).draw(at: CGPoint(x: (bounds.width-sz.width)/2,
                                                y: (bounds.height-sz.height)/2),
                                     withAttributes: attributes)
        }
        let x = target.x * bounds.width
        let y = (1 - target.y) * bounds.height
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: x-14, y: y))
        cross.line(to: CGPoint(x: x-4, y: y))
        cross.move(to: CGPoint(x: x+4, y: y))
        cross.line(to: CGPoint(x: x+14, y: y))
        cross.move(to: CGPoint(x: x, y: y-14))
        cross.line(to: CGPoint(x: x, y: y-4))
        cross.move(to: CGPoint(x: x, y: y+4))
        cross.line(to: CGPoint(x: x, y: y+14))
        cross.lineWidth = 2
        NSColor.systemYellow.setStroke()
        cross.stroke()
    }
}

