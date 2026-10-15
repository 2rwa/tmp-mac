import AppKit
import CoreGraphics
import Darwin

@MainActor
final class StreamMagnifierDelegate: NSObject, NSApplicationDelegate {
    private let preview = ZoomPreview()
    private let status = NSTextField(labelWithString: "起動中")
    private let modeLabel = NSTextField(labelWithString: "移動中：静止画追従")
    let rateLabel = NSTextField(labelWithString: "追従 8fps")
    let settingsRateLabel = NSTextField(labelWithString: "8 fps")
    private let zoomLabel = NSTextField(labelWithString: "4.0×")
    private var window: NSWindow?
    private var timer: Timer?
    private var zoom: CGFloat = 4
    private var paused = false
    var followFPS = 8
    let preferenceKey = "CursorMagnifierStream.cursorFollowFPS"
    var settingsWindow: NSPanel?
    private var policy = CursorMotionPolicy()
    private let snapshots = MovingSnapshot()
    private let video = RegionStream()
    private var phase: CapturePhase?
    private var stationaryTarget = CGPoint(x: 0.5, y: 0.5)
    private var previousSize = CGSize.zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        let stored = UserDefaults.standard.integer(forKey: preferenceKey)
        followFPS = (1...12).contains(stored) ? stored : 8
        rateLabel.stringValue = "追従 \(followFPS)fps"
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 655),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "Cursor Magnifier Stream — Hybrid"
        w.minSize = NSSize(width: 340, height: 550)
        w.center()
        w.level = .floating
        w.isReleasedWhenClosed = false
        self.window = w

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 8
        preview.layer?.masksToBounds = true
        let title = NSTextField(labelWithString: "カーソル追従 + 停止位置の動画")
        title.font = .boldSystemFont(ofSize: 18)
        let hint = NSTextField(labelWithString: "移動中は指定FPSで追従、停止後は動画ストリーム")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let zoomSlider = NSSlider(value: 4, minValue: 2, maxValue: 12,
                                  target: self, action: #selector(zoomChanged(_:)))
        let zoomRow = row([NSTextField(labelWithString: "拡大率"), zoomSlider, zoomLabel])
        let settingsRow = row([
            NSButton(title: "追従FPS設定…", target: self, action: #selector(openSettings)),
            rateLabel, modeLabel
        ])
        let pause = NSButton(title: "一時停止 / 再開", target: self,
                             action: #selector(togglePause))
        let permission = NSButton(title: "画面収録を許可", target: self,
                                  action: #selector(requestPermission))
        let buttons = row([pause, permission])
        status.maximumNumberOfLines = 3
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        modeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let content = NSStackView(views: [title, hint, preview, zoomRow,
                                          settingsRow, buttons, status])
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
            settingsRow.widthAnchor.constraint(equalTo: content.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: content.widthAnchor),
            modeLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
            status.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
        snapshots.onFrame = { [weak self] image, target in
            guard let self, !self.paused, self.phase == .following else { return }
            self.preview.target = target
            self.preview.image = NSImage(cgImage: image,
                size: NSSize(width: image.width, height: image.height))
        }
        snapshots.onError = { [weak self] message in
            guard let self, self.phase == .following else { return }
            self.status.stringValue = message
        }
        video.onFrame = { [weak self] image in
            guard let self, !self.paused, self.phase == .stationary else { return }
            self.preview.target = self.stationaryTarget
            self.preview.image = NSImage(cgImage: image,
                size: NSSize(width: image.width, height: image.height))
        }
        video.onStatus = { [weak self] message in
            guard let self, self.phase == .stationary else { return }
            self.status.stringValue = message
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    func row(_ views: [NSView]) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal
        r.alignment = .centerY
        r.spacing = 10
        return r
    }
    private func resetCapture() {
        snapshots.cancel()
        video.stop()
        policy.invalidate(at: ProcessInfo.processInfo.systemUptime)
        phase = nil
    }

    private func tick() {
        guard !paused else { return }
        guard window?.isVisible == true, window?.isMiniaturized == false else {
            resetCapture()
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            status.stringValue = "画面収録の許可が必要です"
            return
        }
        guard let cursor = CGEvent(source: nil)?.location else { return }
        let size = preview.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        if abs(previousSize.width - size.width) > 1 ||
           abs(previousSize.height - size.height) > 1 {
            previousSize = size
            resetCapture()
        }
        let now = ProcessInfo.processInfo.systemUptime
        let next = policy.sample(cursor, at: now)
        let region = CropGeometry.region(point: cursor, preview: size, zoom: zoom)
        if next != phase {
            phase = next
            modeLabel.stringValue = next.rawValue
            if next == .following {
                video.stop()
                policy.resetSnapshotClock()
                status.stringValue = "カーソル追従中（最大 \(followFPS)fps）"
            } else {
                snapshots.cancel()
                stationaryTarget = region.target(cursor)
                status.stringValue = "停止位置で動画ストリームへ切り替え"
            }
        }
        if next == .following {
            if policy.canRequestSnapshot(at: now, fps: followFPS),
               snapshots.request(region: region, cursor: cursor) {
                policy.markSnapshotRequested(at: now)
            }
        } else {
            video.startIfNeeded(region: region)
        }
    }
    @objc private func zoomChanged(_ sender: NSSlider) {
        zoom = CGFloat(sender.doubleValue)
        zoomLabel.stringValue = String(format: "%.1f×", sender.doubleValue)
        resetCapture()
    }
    @objc private func togglePause() {
        paused.toggle()
        resetCapture()
        status.stringValue = paused ? "一時停止中" : "再開しました"
        if !paused { tick() }
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
        resetCapture()
    }
}

@main
struct StreamMagnifierMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            guard CursorMotionPolicy.selfTest() && CropGeometry.selfTest() else {
                fputs("FAIL: policy or geometry\n", stderr)
                exit(1)
            }
            print("PASS: pointer settle, 1-12fps scheduling and geometry")
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
