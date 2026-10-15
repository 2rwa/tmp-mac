import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit

@MainActor
final class RegionStream {
    var onFrame: ((CGImage) -> Void)?
    var onStatus: ((String) -> Void)?
    private let sink = FrameSink()
    private let queue = DispatchQueue(label: "cursor.magnifier.stream.frames")
    private var stream: SCStream?
    private var running = false
    private var busy = false
    private var current: DisplayRegion?
    private var currentFPS = 0
    private var lastConfigTime: TimeInterval = 0
    private var fastSince: TimeInterval?
    private var generation = 0
    private(set) var configurationUpdates = 0

    init() {
        sink.onFrame = { [weak self] frame in
            guard let self, self.running else { return }
            self.onFrame?(frame)
        }
    }

    func tick(region: DisplayRegion, mode: MotionMode, time: TimeInterval) {
        if mode == .fast {
            if fastSince == nil { fastSince = time }
            if let since = fastSince, time - since >= 0.7,
               running && !busy { pauseCapture() }
            return
        }
        fastSince = nil
        guard !busy else { return }
        let desiredFPS = (mode == .reduced) ? 4 : 12
        if !running {
            startCapture(region: region, fps: desiredFPS, time: time)
        } else if let current {
            if (current.displayID != region.displayID ||
                CropGeometry.shouldRecenter(current.globalRect, region.globalRect) ||
                currentFPS != desiredFPS),
               time - lastConfigTime > 0.12 {
                configure(region: region, fps: desiredFPS, time: time)
            }
        }
    }

    private func configuration(_ region: DisplayRegion, fps: Int) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = region.localRect
        config.width = max(32, Int(ceil(region.globalRect.width * 2)))
        config.height = max(32, Int(ceil(region.globalRect.height * 2)))
        config.scalesToFit = true
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return config
    }

    private func startCapture(region: DisplayRegion, fps: Int, time: TimeInterval) {
        guard !busy else { return }
        busy = true
        generation += 1
        let ticket = generation
        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            do {
                let shareable = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
                guard ticket == self.generation else { return }
                guard let display = shareable.displays.first(where: {
                    $0.displayID == region.displayID
                }) else {
                    self.onStatus?("対象ディスプレイが見つかりません")
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let capture = SCStream(filter: filter,
                                       configuration: self.configuration(region, fps: fps),
                                       delegate: nil)
                try capture.addStreamOutput(self.sink, type: .screen,
                                             sampleHandlerQueue: self.queue)
                self.sink.forceNextFrame()
                try await capture.startCapture()
                self.stream = capture
                self.running = true
                self.current = region
                self.currentFPS = fps
                self.lastConfigTime = time
                self.onStatus?("動画ストリーム起動: \(fps) fps")
            } catch {
                self.running = false
                self.stream = nil
                self.onStatus?("起動失敗: \(error.localizedDescription)")
            }
        }
    }

    private func configure(region: DisplayRegion, fps: Int, time: TimeInterval) {
        guard !busy, let stream else { return }
        if current?.displayID != region.displayID {
            stopCapture(thenStart: region, fps: fps, time: time)
            return
        }
        busy = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            do {
                self.sink.forceNextFrame()
                try await stream.updateConfiguration(self.configuration(region, fps: fps))
                self.current = region
                self.currentFPS = fps
                self.lastConfigTime = time
                self.configurationUpdates += 1
            } catch {
                self.onStatus?("領域変更失敗: \(error.localizedDescription)")
            }
        }
    }

    private func pauseCapture() {
        guard !busy, let stream, running else { return }
        busy = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            do {
                try await stream.stopCapture()
                self.running = false
                self.stream = nil
                self.current = nil
                self.onStatus?("高速移動が継続: キャプチャ停止")
            } catch {
                self.onStatus?("停止失敗: \(error.localizedDescription)")
            }
        }
    }

    private func stopCapture(thenStart region: DisplayRegion, fps: Int,
                             time: TimeInterval) {
        guard !busy, let stream else { return }
        busy = true
        Task { [weak self] in
            guard let self else { return }
            do { try await stream.stopCapture() }
            catch { self.onStatus?("画面切替時の停止失敗: \(error.localizedDescription)") }
            self.running = false
            self.stream = nil
            self.current = nil
            self.busy = false
            self.startCapture(region: region, fps: fps, time: time)
        }
    }

    func stop() {
        generation += 1
        guard let stream else { return }
        self.stream = nil
        running = false
        Task { try? await stream.stopCapture() }
    }
}
