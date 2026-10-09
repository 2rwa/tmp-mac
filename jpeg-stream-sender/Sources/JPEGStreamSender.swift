import AppKit
import Darwin

@MainActor
private final class JPEGStreamSenderDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let server = JPEGServer()
    private let captureStatus = NSTextField(labelWithString: "画面収録を確認中")
    private let networkStatus = NSTextField(labelWithString: "TCPサーバ起動中")
    private let zoomText = NSTextField(labelWithString: "4.0×")
    private let qualityText = NSTextField(labelWithString: "70%")
    private let fpsText = NSTextField(labelWithString: "12 fps")
    private let pauseButton = NSButton(title: "一時停止", target: nil, action: nil)
    private var timer: Timer?
    private var zoom: CGFloat = 4
    private var quality: CGFloat = 0.7
    private var fps: Double = 12
    private var paused = false
    private lazy var capture = StreamCapture(server: server, status: captureStatus)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 345),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "JPEG Stream Sender（Mac → Android）"
        w.center()
        w.isReleasedWhenClosed = false
        self.window = w
        let header = NSTextField(labelWithString: "Android 5.1+ へのJPEG拡大鏡配信")
        header.font = .boldSystemFont(ofSize: 18)
        let help = NSTextField(wrappingLabelWithString:
            "同じLANのAndroidで「JPEG Stream Viewer」を開き、MacのIPアドレスとTCP 5055で接続します。拡大率が高いほど切り出す元画像は小さくなります。")
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: 12)
        let zoomSlider = NSSlider(value: 4, minValue: 1, maxValue: 16, target: self, action: #selector(zoomChanged(_:)))
        let qualitySlider = NSSlider(value: 0.7, minValue: 0.2, maxValue: 0.95, target: self, action: #selector(qualityChanged(_:)))
        let fpsSlider = NSSlider(value: 12, minValue: 1, maxValue: 20, target: self, action: #selector(fpsChanged(_:)))
        zoomText.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        qualityText.font = zoomText.font
        fpsText.font = zoomText.font
        let zoomRow = makeRow(label: "拡大率", slider: zoomSlider, text: zoomText)
        let qualityRow = makeRow(label: "JPEG品質", slider: qualitySlider, text: qualityText)
        let fpsRow = makeRow(label: "送信fps", slider: fpsSlider, text: fpsText)
        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        let permissionButton = NSButton(title: "画面収録の許可 / 再確認", target: self, action: #selector(permission))
        let controls = NSStackView(views: [pauseButton, permissionButton])
        controls.orientation = .horizontal
        controls.spacing = 8
        networkStatus.font = .systemFont(ofSize: 12)
        captureStatus.font = .systemFont(ofSize: 12)
        networkStatus.textColor = .secondaryLabelColor
        captureStatus.textColor = .secondaryLabelColor
        let column = NSStackView(views: [
            header, help, zoomRow, qualityRow, fpsRow, controls, networkStatus, captureStatus
        ])
        column.orientation = .vertical
        column.spacing = 10
        column.alignment = .leading
        column.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        w.contentView = root
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            column.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -12),
            help.widthAnchor.constraint(equalTo: column.widthAnchor),
            zoomRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            qualityRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            fpsRow.widthAnchor.constraint(equalTo: column.widthAnchor)
        ])
        server.onStatus = { [weak self] message in self?.networkStatus.stringValue = message }
        server.start()
        capture.start()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 25.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.capture.tick(zoom: self.zoom, quality: self.quality, fps: self.fps)
            }
        }
        if CommandLine.arguments.contains("--window-smoke") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) }
        }
    }

    private func makeRow(label: String, slider: NSSlider, text: NSTextField) -> NSStackView {
        let caption = NSTextField(labelWithString: label)
        caption.font = .systemFont(ofSize: 12)
        caption.widthAnchor.constraint(equalToConstant: 75).isActive = true
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let row = NSStackView(views: [caption, slider, text])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    @objc private func zoomChanged(_ sender: NSSlider) {
        zoom = CGFloat(sender.doubleValue)
        zoomText.stringValue = String(format: "%.1f×", sender.doubleValue)
    }
    @objc private func qualityChanged(_ sender: NSSlider) {
        quality = CGFloat(sender.doubleValue)
        qualityText.stringValue = String(format: "%.0f%%", sender.doubleValue * 100)
    }
    @objc private func fpsChanged(_ sender: NSSlider) {
        fps = sender.doubleValue
        fpsText.stringValue = String(format: "%.0f fps", fps)
    }
    @objc private func togglePause() {
        paused.toggle()
        pauseButton.title = paused ? "再開" : "一時停止"
        capture.setPaused(paused)
    }
    @objc private func permission() { capture.requestPermission() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        capture.stop()
        server.stop()
    }
}

@main
private struct StreamMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            guard StreamGeometry.selfTest() else {
                fputs("FAIL: stream crop geometry\n", stderr)
                exit(1)
            }
            print("PASS: screen crop/edge clamping/cursor positions")
        } else {
            MainActor.assumeIsolated {
                let app = NSApplication.shared
                app.setActivationPolicy(.regular)
                let delegate = JPEGStreamSenderDelegate()
                app.delegate = delegate
                app.run()
            }
        }
    }
}
