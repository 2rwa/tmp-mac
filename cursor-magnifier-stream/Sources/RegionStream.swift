import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit

// Single, independently throttled screenshots while the mouse is moving.
@MainActor
final class MovingSnapshot {
    var onFrame: ((CGImage, CGPoint) -> Void)?
    var onError: ((String) -> Void)?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var busy = false

    @discardableResult
    func request(region: DisplayRegion, cursor: CGPoint) -> Bool {
        guard !busy else { return false }
        busy = true
        let expected = generation
        let target = region.target(cursor)
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            do {
                let cgImage = try await SCScreenshotManager.captureImage(in: region.globalRect)
                guard !Task.isCancelled, self.generation == expected else { return }
                self.onFrame?(cgImage, target)
            } catch {
                guard self.generation == expected, !Task.isCancelled else { return }
                self.onError?("追従画像の取得に失敗: \(error.localizedDescription)")
            }
        }
        return true
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }
}

// A stationary crop uses a video stream. Cursor movement invalidates startup
// and stops the stream; there is no high-speed motion suppression or crop
// reconfiguration during movement.
@MainActor
final class RegionStream {
    var onFrame: ((CGImage) -> Void)?
    var onStatus: ((String) -> Void)?
    private let queue = DispatchQueue(label: "cursor.magnifier.hybrid.video")
    private var stream: SCStream?
    private var frameSink: FrameSink?
    private var currentRegion: DisplayRegion?
    private var starting = false
    private var generation = 0

    func startIfNeeded(region: DisplayRegion) {
        guard stream == nil, !starting else { return }
        starting = true
        generation += 1
        let expected = generation
        Task { [weak self] in
            guard let self else { return }
            defer { self.starting = false }
            do {
                let available = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
                guard self.generation == expected else { return }
                guard let display = available.displays.first(where: {
                    $0.displayID == region.displayID
                }) else {
                    self.onStatus?("対象ディスプレイが見つかりません")
                    return
                }
                let config = SCStreamConfiguration()
                config.sourceRect = region.localRect
                config.width = max(32, Int(ceil(region.globalRect.width * 2)))
                config.height = max(32, Int(ceil(region.globalRect.height * 2)))
                config.scalesToFit = true
                config.showsCursor = false
                config.minimumFrameInterval = CMTime(value: 1, timescale: 12)
                config.queueDepth = 3
                config.pixelFormat = kCVPixelFormatType_32BGRA

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let capture = SCStream(filter: filter, configuration: config, delegate: nil)
                let sink = FrameSink()
                sink.onFrame = { [weak self] frame in
                    guard let self, self.generation == expected else { return }
                    self.onFrame?(frame)
                }
                sink.forceNextFrame()
                try capture.addStreamOutput(sink, type: .screen,
                                            sampleHandlerQueue: self.queue)
                try await capture.startCapture()
                guard self.generation == expected else {
                    try? await capture.stopCapture()
                    return
                }
                self.frameSink = sink
                self.stream = capture
                self.currentRegion = region
                self.onStatus?("停止位置で動画ストリーム 12fps")
                // SCStream retains the output as long as it remains registered.
            } catch {
                guard self.generation == expected else { return }
                self.onStatus?("動画ストリーム起動失敗: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        generation += 1
        currentRegion = nil
        frameSink = nil
        guard let old = stream else { return }
        stream = nil
        Task { try? await old.stopCapture() }
    }

    var isRunning: Bool { stream != nil }
}
