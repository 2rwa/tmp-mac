import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit

// SCStream's sourceRect already clips the video. The dirty rect metadata refers to
// the clipped video; an empty array means there is no change worth redrawing.
final class FrameSink: NSObject, SCStreamOutput {
    var onFrame: ((CGImage) -> Void)?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let lock = NSLock()
    private var needsFreshFrame = true
    private var pending = false
    private(set) var framesAccepted = 0

    func forceNextFrame() {
        lock.lock(); needsFreshFrame = true; lock.unlock()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                  sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachmentsArray.first,
              let rawStatus = info[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus),
              status == .complete || status == .started,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lock.lock()
        let forced = needsFreshFrame
        if let dirty = info[.dirtyRects] as? [Any], dirty.isEmpty && !forced {
            lock.unlock()
            return
        }
        if pending {
            lock.unlock()
            return
        }
        pending = true
        needsFreshFrame = false
        lock.unlock()

        let input = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(input, from: input.extent) else {
            lock.lock(); pending = false; needsFreshFrame = true; lock.unlock()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onFrame?(cgImage)
            self.lock.lock()
            self.pending = false
            self.framesAccepted += 1
            self.lock.unlock()
        }
    }
}
