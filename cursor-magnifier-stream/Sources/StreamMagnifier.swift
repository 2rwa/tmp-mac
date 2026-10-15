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

@MainActor
final class StreamMagnifierDelegate: NSObject, NSApplicationDelegate {
    private let preview = ZoomPreview()
    private let status = NSTextField(labelWithString: "起動中")
    private let modeLabel = NSTextField(labelWithString: "通常 12fps")
    private let zoomLabel = NSTextField(labelWithString: "4.0×")
    private var window: NSWindow?
    private var timer: Timer?
    private var zoom: CGFloat = 4
    private var paused = false
    private var policy = MotionPolicy()
    private let capture = RegionStream()
    private var lastMode: MotionMode?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 655),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "Cursor Magnifier Stream"
        w.minSize = NSSize(width: 340, height: 550)
        w.center()
        w.level = .floating
        w.isReleasedWhenClosed = false
        self.window = w

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 8
        preview.layer?.masksToBounds = true
        let title = NSTextField(labelWithString: "低負荷・動画ストリーム拡大鏡")
        title.font = .boldSystemFont(ofSize: 18)
        let hint = NSTextField(labelWithString: "画面の差分のみ描画 / 高速マウス移動時は抑制")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let zoomSlider = NSSlider(value: 4, minValue: 2, maxValue: 12,
                                  target: self, action: #selector(zoomChanged(_:)))
        let zoomRow = row([NSTextField(labelWithString: "拡大率"), zoomSlider, zoomLabel])
        let pause = NSButton(title: "一時停止 / 再開", target: self,
                             action: #selector(togglePause))
        let permission = NSButton(title: "画面収録を許可", target: self,
                                  action: #selector(requestPermission))
        let buttons = row([pause, permission])
        status.maximumNumberOfLines = 3
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        modeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let content = NSStackView(views: [title, hint, preview, zoomRow, buttons,
                                          modeLabel, status])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        w.contentView = root
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            content.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -14),
            preview.widthAnchor.constraint(equalTo: content.widthAnchor),
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor),
            zoomRow.widthAnchor.constraint(equalTo: content.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: content.widthAnchor),
            modeLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
            status.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
        capture.onFrame = { [weak self] image in
            guard let self, !self.paused else { return }
            self.preview.image = NSImage(cgImage: image,
                                         size: NSSize(width: image.width, height: image.height))
        }
        capture.onStatus = { [weak self] message in self?.status.stringValue = message }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal
        r.alignment = .centerY
        r.spacing = 10
        return r
    }
    private func tick() {
        guard window?.isVisible == true, !paused else { return }
        guard CGPreflightScreenCaptureAccess() else {
            if status.stringValue != "画面収録の許可が必要です" {
                status.stringValue = "画面収録の許可が必要です"
            }
            return
        }
        guard let cursor = CGEvent(source: nil)?.location else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let mode = policy.sample(cursor, at: now)
        if lastMode != mode {
            lastMode = mode
            modeLabel.stringValue = mode.rawValue
        }
        guard preview.bounds.width > 0, preview.bounds.height > 0 else { return }
        let region = CropGeometry.region(point: cursor, preview: preview.bounds.size,
                                         zoom: zoom)
        capture.tick(region: region, mode: mode, time: now)
        if mode != .fast { preview.target = region.target(cursor) }
    }
    @objc private func zoomChanged(_ sender: NSSlider) {
        zoom = CGFloat(sender.doubleValue)
        zoomLabel.stringValue = String(format: "%.1f×", sender.doubleValue)
    }
    @objc private func togglePause() {
        paused.toggle()
        if paused { capture.stop(); status.stringValue = "一時停止中" }
        else { tick() }
    }
    @objc private func requestPermission() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            status.stringValue = "許可後はアプリを再起動してください"
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        capture.stop()
    }
}

@main
struct StreamMagnifierMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            guard MotionPolicy.selfTest() && CropGeometry.selfTest() else {
                fputs("FAIL: policy or geometry\n", stderr)
                exit(1)
            }
            print("PASS: mouse speed hysteresis and capture geometry")
        } else {
            MainActor.assumeIsolated {
                let app = NSApplication.shared
                app.setActivationPolicy(.regular)
                let delegate = StreamMagnifierDelegate()
                app.delegate = delegate
                app.run()
            }
        }
    }
}
