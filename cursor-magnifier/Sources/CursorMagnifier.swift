import AppKit
import CoreGraphics
import ScreenCaptureKit
import Darwin

@MainActor
private final class MagnifierAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let preview = MagnifierPreview()
    private let zoomValue = NSTextField(labelWithString: "4.0×")
    private let status = NSTextField(labelWithString: "")
    private let pauseButton = NSButton(title: "一時停止", target: nil, action: nil)
    private let topButton = NSButton(checkboxWithTitle: "最前面に表示", target: nil, action: nil)
    private var timer: Timer?
    private var paused = false
    private var zoom: CGFloat = 4
    private lazy var capture = CaptureSession(preview: preview, status: status)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Cursor Magnifier"
        window.minSize = NSSize(width: 340, height: 540)
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        self.window = window

        let title = NSTextField(labelWithString: "カーソル周辺の拡大表示")
        title.font = .boldSystemFont(ofSize: 19)
        let help = NSTextField(labelWithString: "マウスの周囲をリアルタイムで拡大します")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 8
        preview.layer?.masksToBounds = true
        preview.translatesAutoresizingMaskIntoConstraints = false

        let zoomTitle = NSTextField(labelWithString: "拡大率")
        let slider = NSSlider(value: 4, minValue: 2, maxValue: 12,
                              target: self, action: #selector(zoomChanged(_:)))
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        zoomTitle.setContentHuggingPriority(.required, for: .horizontal)
        zoomValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        zoomValue.alignment = .right
        zoomValue.setContentHuggingPriority(.required, for: .horizontal)
        let zoomRow = horizontal([zoomTitle, slider, zoomValue])

        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        topButton.state = .on
        topButton.target = self
        topButton.action = #selector(toggleAlwaysOnTop)
        let controlRow = horizontal([pauseButton, topButton])
        let permissionRow = horizontal([
            NSButton(title: "画面収録の許可 / 再確認", target: self,
                     action: #selector(requestPermission)),
            NSButton(title: "システム設定", target: self,
                     action: #selector(openPrivacySettings))
        ])

        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        status.maximumNumberOfLines = 2
        status.lineBreakMode = .byWordWrapping
        let column = NSStackView(views: [
            title, help, preview, zoomRow, controlRow, permissionRow, status
        ])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        window.contentView = root
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            column.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -14),
            preview.widthAnchor.constraint(equalTo: column.widthAnchor),
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor),
            zoomRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            controlRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            permissionRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            status.widthAnchor.constraint(equalTo: column.widthAnchor)
        ])
        capture.start()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // At most one screenshot request is in progress at a time.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.capture.tick(visible: self.window?.isVisible == true, zoom: self.zoom)
            }
        }
        if CommandLine.arguments.contains("--window-smoke") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        capture.stop()
    }

    private func horizontal(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }

    @objc private func zoomChanged(_ sender: NSSlider) {
        zoom = CGFloat(sender.doubleValue)
        zoomValue.stringValue = String(format: "%.1f×", sender.doubleValue)
    }

    @objc private func togglePause() {
        paused.toggle()
        pauseButton.title = paused ? "再開" : "一時停止"
        capture.setPaused(paused)
    }

    @objc private func toggleAlwaysOnTop() {
        window?.level = topButton.state == .on ? .floating : .normal
    }

    @objc private func requestPermission() {
        capture.requestPermission()
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }


}

@main
private struct CursorMagnifierMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            guard CaptureGeometry.selfTest() && CaptureState.selfTest() else {
                fputs("FAIL: cursor crop geometry\n", stderr)
                exit(1)
            }
            print("PASS: zoom crop, cursor mapping, sleep/wake holds, stale callback, timeout and retry")
        } else {
            MainActor.assumeIsolated {
                let app = NSApplication.shared
                app.setActivationPolicy(.regular)
                let delegate = MagnifierAppDelegate()
                app.delegate = delegate
                app.run()
            }
        }
    }
}
