import AppKit
import CoreGraphics

enum CapturePhase: String {
    case following = "移動中：静止画追従"
    case stationary = "停止中：動画ストリーム"
}

// Pointer motion is sampled independently from the requested screenshot FPS.
// A positional tolerance prevents a tiny jitter from repeatedly restarting SCStream.
struct CursorMotionPolicy {
    private var anchor: CGPoint?
    private var lastMotionTime: TimeInterval = 0
    private var lastSnapshotTime = -Double.infinity
    private(set) var phase: CapturePhase = .following
    let settleDelay: TimeInterval = 0.25
    let movementTolerance: CGFloat = 1.5

    mutating func sample(_ point: CGPoint, at now: TimeInterval) -> CapturePhase {
        guard let anchor else {
            self.anchor = point
            lastMotionTime = now
            phase = .following
            return phase
        }
        if hypot(point.x - anchor.x, point.y - anchor.y) >= movementTolerance {
            self.anchor = point
            lastMotionTime = now
            phase = .following
        } else if now - lastMotionTime >= settleDelay {
            phase = .stationary
        }
        return phase
    }

    mutating func invalidate(at now: TimeInterval) {
        anchor = nil
        lastMotionTime = now
        lastSnapshotTime = -.infinity
        phase = .following
    }

    func canRequestSnapshot(at now: TimeInterval, fps: Int) -> Bool {
        let rate = max(1, min(12, fps))
        return now - lastSnapshotTime >= 1.0 / Double(rate)
    }

    mutating func markSnapshotRequested(at now: TimeInterval) {
        lastSnapshotTime = now
    }

    mutating func resetSnapshotClock() {
        lastSnapshotTime = -.infinity
    }

    static func selfTest() -> Bool {
        var p = CursorMotionPolicy()
        guard p.sample(.zero, at: 0) == .following,
              p.canRequestSnapshot(at: 0, fps: 1),
              p.sample(.zero, at: 0.01) == .following
        else { return false }
        p.markSnapshotRequested(at: 0)
        guard !p.canRequestSnapshot(at: 0.8, fps: 1),
              p.canRequestSnapshot(at: 1.01, fps: 1),
              p.sample(CGPoint(x: 50, y: 0), at: 1.1) == .following,
              p.sample(CGPoint(x: 50.5, y: 0), at: 1.2) == .following,
              p.sample(CGPoint(x: 50.5, y: 0), at: 1.36) == .stationary,
              p.sample(CGPoint(x: 65, y: 0), at: 1.4) == .following
        else { return false }
        p.invalidate(at: 1.41)
        guard p.sample(CGPoint(x: 65, y: 0), at: 1.42) == .following,
              p.canRequestSnapshot(at: 1.42, fps: 12) else { return false }
        p.markSnapshotRequested(at: 1.42)
        guard !p.canRequestSnapshot(at: 1.45, fps: 12),
              p.canRequestSnapshot(at: 1.51, fps: 12) else { return false }
        return true
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
