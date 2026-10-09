import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class CaptureSession: NSObject {
    private let preview: MagnifierPreview
    private let status: NSTextField
    private var state = CaptureState()
    private var captureTask: Task<Void, Never>?
    private var unfinished = 0
    private var paused = false
    private var lastError: String?
    private var hasObservers = false

    init(preview: MagnifierPreview, status: NSTextField) {
        self.preview = preview
        self.status = status
        super.init()
    }

    func start() {
        guard !hasObservers else { return }
        hasObservers = true
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(systemSleeping(_:)),
                       name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(systemAwake(_:)),
                       name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(screenSleeping(_:)),
                       name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(screenAwake(_:)),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(sessionInactive(_:)),
                       name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(sessionActive(_:)),
                       name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        refreshPermissionStatus()
    }

    func stop() {
        captureTask?.cancel()
        state.suspend(.inactiveSession)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        hasObservers = false
    }

    func setPaused(_ value: Bool) {
        paused = value
        captureTask?.cancel()
        state.reset(at: Date(), delay: value ? 0 : 0.2)
        if value { status.stringValue = "停止中：最後のフレームを表示しています" }
        else { refreshPermissionStatus() }
    }

    func requestPermission() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        refreshPermissionStatus()
    }

    func refreshPermissionStatus() {
        if !state.holds.isEmpty {
            status.stringValue = "Mac / 画面がスリープ中：キャプチャ停止"
        } else if !CGPreflightScreenCaptureAccess() {
            status.stringValue = "画面収録の許可が必要です。許可後はアプリを再起動してください。"
        } else if paused {
            status.stringValue = "停止中：最後のフレームを表示しています"
        } else {
            status.stringValue = "画面収録：許可済み / 12 fps（目標）"
        }
    }

    @objc private func systemSleeping(_ notification: Notification) {
        suspend(.systemSleep)
    }
    @objc private func systemAwake(_ notification: Notification) {
        resume(.systemSleep)
    }
    @objc private func screenSleeping(_ notification: Notification) {
        suspend(.screenSleep)
    }
    @objc private func screenAwake(_ notification: Notification) {
        resume(.screenSleep)
    }
    @objc private func sessionInactive(_ notification: Notification) {
        suspend(.inactiveSession)
    }
    @objc private func sessionActive(_ notification: Notification) {
        resume(.inactiveSession)
    }
    @objc private func screensChanged(_ notification: Notification) {
        captureTask?.cancel()
        state.reset(at: Date(), delay: 2)
        preview.image = nil
        status.stringValue = "画面構成の変更を検出：キャプチャ再準備中"
    }

    private func suspend(_ reason: CaptureHold) {
        state.suspend(reason)
        captureTask?.cancel()
        preview.image = nil
        status.stringValue = "スリープ / セッション切替中：キャプチャ停止"
    }

    private func resume(_ reason: CaptureHold) {
        state.resume(reason, at: Date())
        captureTask?.cancel()
        preview.image = nil
        if state.holds.isEmpty {
            status.stringValue = "画面復帰を検出：2秒後に再開します"
        } else {
            status.stringValue = "ほかのスリープ状態が解除されるまで待機中"
        }
    }

    func tick(visible: Bool, zoom: CGFloat) {
        guard visible, !paused else { return }
        let now = Date()
        if state.expireIfNeeded(at: now) {
            captureTask?.cancel()
            status.stringValue = "画面取得がタイムアウト。再試行します"
        }
        guard state.canStart(at: now) else { return }
        // Bound requests if the OS never completes cancelled screenshot calls.
        guard unfinished < 2 else {
            status.stringValue = "画面取得の応答待ちです。続く場合はアプリを再起動してください。"
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            refreshPermissionStatus()
            return
        }
        guard let cursor = CGEvent(source: nil)?.location else {
            status.stringValue = "マウス位置を取得できません"
            return
        }
        let size = preview.bounds.size
        guard size.width > 0 && size.height > 0 else { return }
        let region = CaptureGeometry.rect(
            around: cursor, in: CaptureGeometry.display(containing: cursor),
            preview: size, zoom: zoom
        )
        guard region.width >= 1 && region.height >= 1 else { return }
        let point = CaptureGeometry.relativeCursor(cursor, in: region)
        guard let token = state.begin(at: now) else { return }
        unfinished += 1
        captureTask = Task { @MainActor [weak self] in
            defer { self?.unfinished -= 1 }
            do {
                let image = try await SCScreenshotManager.captureImage(in: region)
                guard let self,
                      self.state.finish(token, succeeded: true, at: Date()),
                      !self.paused else { return }
                self.preview.image = NSImage(cgImage: image, size: region.size)
                self.preview.target = point
                if self.lastError != nil {
                    self.lastError = nil
                    self.refreshPermissionStatus()
                }
            } catch {
                guard let self,
                      self.state.finish(token, succeeded: false, at: Date()) else { return }
                let message = error.localizedDescription
                if message != self.lastError {
                    self.lastError = message
                    self.status.stringValue = "キャプチャ失敗（自動再試行）：\(message)"
                }
            }
        }
    }
}
