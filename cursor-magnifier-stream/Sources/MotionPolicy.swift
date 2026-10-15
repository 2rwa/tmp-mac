import AppKit
import CoreGraphics

enum MotionMode: String {
    case normal = "通常 12fps"
    case reduced = "移動中 4fps"
    case fast = "高速移動・更新抑制"
}

struct MotionPolicy {
    private(set) var mode: MotionMode = .normal
    private var previousPoint: CGPoint?
    private var previousTime: TimeInterval?
    private var filteredSpeed = 0.0
    private var calmSince: TimeInterval?

    mutating func sample(_ point: CGPoint, at now: TimeInterval) -> MotionMode {
        defer { previousPoint = point; previousTime = now }
        guard let before = previousPoint, let time = previousTime,
              now > time, now - time < 0.5 else {
            filteredSpeed = 0
            return mode
        }
        let speed = Double(hypot(point.x - before.x, point.y - before.y))
            / (now - time)
        filteredSpeed = filteredSpeed * 0.5 + speed * 0.5
        switch mode {
        case .normal:
            if filteredSpeed > 900 { mode = .fast; calmSince = nil }
            else if filteredSpeed > 150 { mode = .reduced }
        case .reduced:
            if filteredSpeed > 900 { mode = .fast; calmSince = nil }
            else if filteredSpeed < 100 { mode = .normal }
        case .fast:
            if filteredSpeed < 350 {
                if calmSince == nil { calmSince = now }
                if let since = calmSince, now - since >= 0.18 {
                    mode = filteredSpeed > 150 ? .reduced : .normal
                    calmSince = nil
                }
            } else { calmSince = nil }
        }
        return mode
    }

    static func selfTest() -> Bool {
        var p = MotionPolicy()
        _ = p.sample(.zero, at: 0)
        guard p.sample(CGPoint(x: 100, y: 0), at: 0.033) == .fast else { return false }
        for i in 2...12 { _ = p.sample(CGPoint(x: 100, y: 0), at: Double(i) * 0.033) }
        return p.mode == .normal
    }
}

struct DisplayRegion {
    let displayID: CGDirectDisplayID
    let displayBounds: CGRect
    let globalRect: CGRect

    var localRect: CGRect {
        CGRect(x: globalRect.minX - displayBounds.minX,
               y: globalRect.minY - displayBounds.minY,
               width: globalRect.width, height: globalRect.height)
    }
    func target(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - globalRect.minX) / globalRect.width,
                y: (point.y - globalRect.minY) / globalRect.height)
    }
}

enum CropGeometry {
    static func display(containing cursor: CGPoint) -> (CGDirectDisplayID, CGRect) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        if CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success {
            for id in ids.prefix(Int(count)) {
                let frame = CGDisplayBounds(id)
                if frame.contains(cursor) { return (id, frame) }
            }
        }
        let id = CGMainDisplayID()
        return (id, CGDisplayBounds(id))
    }
    static func region(point: CGPoint, preview: CGSize, zoom: CGFloat) -> DisplayRegion {
        let (id, display) = self.display(containing: point)
        let w = min(display.width, max(1, preview.width / max(zoom, 1)))
        let h = min(display.height, max(1, preview.height / max(zoom, 1)))
        let x = min(max(point.x - w / 2, display.minX), display.maxX - w)
        let y = min(max(point.y - h / 2, display.minY), display.maxY - h)
        return DisplayRegion(displayID: id, displayBounds: display,
                             globalRect: CGRect(x: x, y: y, width: w, height: h))
    }
    static func shouldRecenter(_ a: CGRect, _ b: CGRect) -> Bool {
        let threshold = max(3, min(a.width, a.height) * 0.12)
        return hypot(a.midX - b.midX, a.midY - b.midY) > threshold
            || abs(a.width - b.width) > 0.1 || abs(a.height - b.height) > 0.1
    }
    static func selfTest() -> Bool {
        let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let r = DisplayRegion(displayID: 1, displayBounds: display,
                              globalRect: CGRect(x: -1100, y: 100, width: 100, height: 100))
        let local = r.localRect
        return local.minX == 820 && local.minY == 100
            && r.target(CGPoint(x: -1050, y: 150)) == CGPoint(x: 0.5, y: 0.5)
            && !shouldRecenter(r.globalRect, r.globalRect)
            && shouldRecenter(r.globalRect, r.globalRect.offsetBy(dx: 20, dy: 0))
    }
}
