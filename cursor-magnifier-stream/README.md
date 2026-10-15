# Cursor Magnifier Stream (low-overhead experiment)

A **separate app** from `cursor-magnifier/`. Swift/AppKit + ScreenCaptureKit,
macOS 15.2+, Apple Silicon. No screenshot polling, no video file encoding.

## Design

- Uses `SCStream` instead of requesting 12 standalone screenshots per second.
- Captures only a small `sourceRect` around the cursor, not the full display.
- Handles `SCFrameStatus.idle`, plus empty `SCStreamFrameInfo.dirtyRects`;
  unchanged frames are not converted from CVPixelBuffer to CGImage or redrawn.
- Motion policy polls the pointer at 30Hz: normal 12fps, medium 4fps, high
  motion freezes preview; high motion lasting over 700ms stops capture.
- 180ms of sufficiently slow motion re-enables capture. Hysteresis avoids
  rapid stop/restart. Updating the crop has a movement threshold and 120ms
  minimum interval. No permanent stream reconfiguration each pointer tick.
- CIContext is reused for converting changed video frames to CGImage;
  the rest of the capture path uses native ScreenCaptureKit buffers.
- Output frames are not compressed or written to disk.

**Caveats:** ScreenCaptureKit still has WindowServer/capture overhead while
streaming; dirtyRects only saves downstream work. The crop is moved with
`SCStream.updateConfiguration` as required, which can incur overhead.
A new crop is forced to render when an output frame arrives. Mouse movement
alone need not dirty the captured display if the OS hides the pointer from
the capture; we explicitly request a frame after a crop change.

## Open directly in Xcode

1. Open **`CursorMagnifierStream.xcodeproj`** from the repository root in Xcode.
2. Select the shared **CursorMagnifierStream** scheme and **My Mac**.
3. Press **Command-R** (Run) or **Command-B** (Build).
4. Grant Screen Recording permission when prompted, then restart the app.

If you are downloading from Actions, unpack `CursorMagnifierStream-Xcode-source.zip`.
It contains both the `.xcodeproj` and the Swift sources with their
relative paths intact. No manual source-file registration, Package.swift,
or shell commands are required.

## Build

A GitHub Actions macOS ARM64 job automatically runs on pushes to this
directory or on manual dispatch:
[Actions: Cursor Magnifier Stream](../../actions/workflows/cursor-magnifier-stream.yml).

Download the `cursor-magnifier-stream-macos-arm64` artifact, unzip
`CursorMagnifierStream-arm64.zip`, and open the app on a Mac.
The app uses an ad-hoc signature, not Developer ID or notarization.
You may need to open it through System Settings > Privacy & Security.

Local compilation (requires Xcode command line tools):
```bash
bash cursor-magnifier-stream/build.sh
cursor-magnifier-stream/build/CursorMagnifierStream.app/Contents/MacOS/CursorMagnifierStream --self-test
```

The GUI needs macOS **Screen & System Audio Recording** authorization.
Click `画面収録を許可`, then restart the app after granting the permission.

The Actions runner has no user-granted screen-capture permission:
it can compile, sign and self-test but **cannot validate actual capture,
cursor tracking, CPU or WindowServer load**. Test those on a real Mac.

## Suggested performance experiment

Compare the existing `cursor-magnifier/` and this stream build with
Activity Monitor's CPU and WindowServer columns for 60 seconds each:
idle pointer, slow cursor tracking, fast cursor motion, and playing a
video under the lens. Also compare delay on fast-motion recovery.
