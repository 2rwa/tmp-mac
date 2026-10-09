import AppKit
import CoreGraphics
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class StreamCapture: NSObject {
    private enum Hold: Hashable { case system, display, session }
    private let server: JPEGServer
    private let status: NSTextField
    private var holds = Set<Hold>()
    private var generation: UInt64 = 0
    private var inFlightToken: UInt64?
    private var request: Task<Void, Never>?
    private var unfinished = 0
    private var retryAfter = Date.distantPast
    private var failures = 0
    private var lastStart = Date.distantPast
    private var paused = false
    private var installed = false

    init(server: JPEGServer, status: NSTextField) {
        self.server = server
        self.status = status
        super.init()
    }

    func start() {
        guard !installed else { return }
        installed = true
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(systemSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(systemWake), name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(displaySleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(displayWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(sessionSleep), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(sessionWake), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refreshPermission()
    }

    func stop() {
        invalidate(delay: 0)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        installed = false
    }

    func setPaused(_ value: Bool) {
        paused = value
        invalidate(delay: value ? 0 : 0.2)
        status.stringValue = value ? "一時停止中" : "再開しました"
    }

    func requestPermission() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        refreshPermission()
    }

    private func refreshPermission() {
        status.stringValue = CGPreflightScreenCaptureAccess()
            ? "画面収録：許可済み" : "画面収録の許可が必要です。許可後は再起動してください"
    }

    private func invalidate(delay: TimeInterval) {
        generation &+= 1
        inFlightToken = nil
        request?.cancel()
        retryAfter = Date().addingTimeInterval(delay)
        failures = 0
    }

    @objc private func systemSleep(_ n: Notification) { suspend(.system) }
    @objc private func systemWake(_ n: Notification) { resume(.system) }
    @objc private func displaySleep(_ n: Notification) { suspend(.display) }
    @objc private func displayWake(_ n: Notification) { resume(.display) }
    @objc private func sessionSleep(_ n: Notification) { suspend(.session) }
    @objc private func sessionWake(_ n: Notification) { resume(.session) }
    @objc private func screensChanged(_ n: Notification) {
        invalidate(delay: 2)
        status.stringValue = "画面構成変更：2秒後に再開"
    }

    private func suspend(_ reason: Hold) {
        holds.insert(reason)
        invalidate(delay: 2)
        status.stringValue = "Mac / ディスプレイ休止中：送信停止"
    }
    private func resume(_ reason: Hold) {
        holds.remove(reason)
        invalidate(delay: 2)
        status.stringValue = holds.isEmpty ? "画面復帰：2秒後に再開" : "ほかの休止解除を待機中"
    }

    func tick(zoom: CGFloat, quality: CGFloat, fps: Double) {
        let now = Date()
        guard !paused, holds.isEmpty, now >= retryAfter else { return }
        if let token = inFlightToken, now.timeIntervalSince(lastStart) >= 6 {
            guard token == generation else { return }
            inFlightToken = nil
            request?.cancel()
            failures = min(failures + 1, 10)
            retryAfter = now.addingTimeInterval(min(16, pow(2, Double(failures - 1))))
            status.stringValue = "キャプチャ応答待ちでタイムアウト：再試行"
            return
        }
        guard inFlightToken == nil, unfinished < 2,
              now.timeIntervalSince(lastStart) >= 1.0 / max(1, fps) else { return }
        guard CGPreflightScreenCaptureAccess() else { refreshPermission(); return }
        guard let cursor = CGEvent(source: nil)?.location else { return }
        let area = StreamGeometry.rect(cursor: cursor, display: StreamGeometry.display(containing: cursor),
                                       frame: CGSize(width: 640, height: 360), zoom: zoom)
        guard area.width > 0 && area.height > 0 else { return }
        let pt = StreamGeometry.normalizedCursor(cursor, rect: area)
        generation &+= 1
        let token = generation
        inFlightToken = token
        lastStart = now
        unfinished += 1
        request = Task { @MainActor [weak self] in
            defer { self?.unfinished -= 1 }
            do {
                let image = try await SCScreenshotManager.captureImage(in: area)
                guard let self, self.generation == token,
                      self.inFlightToken == token, !self.paused, self.holds.isEmpty else { return }
                self.inFlightToken = nil
                let output = NSMutableData()
                if let encoder = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(encoder, image,
                        [kCGImageDestinationLossyCompressionQuality: Double(quality)] as CFDictionary)
                    if CGImageDestinationFinalize(encoder) {
                        self.server.submit(jpeg: output as Data, cursorX: pt.0, cursorY: pt.1)
                        self.failures = 0
                        return
                    }
                }
                self.markFailure("JPEGエンコード失敗")
            } catch {
                guard let self, self.generation == token else { return }
                self.inFlightToken = nil
                self.markFailure("キャプチャ失敗: \(error.localizedDescription)")
            }
        }
    }

    private func markFailure(_ message: String) {
        failures = min(failures + 1, 10)
        retryAfter = Date().addingTimeInterval(min(16, pow(2, Double(failures - 1))))
        status.stringValue = message
    }
}
