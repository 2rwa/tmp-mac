# Cursor Magnifier Stream — Hybrid v0.2

A separate native macOS magnifier in `2rwa/tmp-mac`, independent of the original
`cursor-magnifier/` screenshot-only application. Requires macOS 15.2+
(Apple Silicon recommended).

## Cursor behavior

- **While the pointer is moving:** request independent pointer-centered screenshots
  at a **configurable 1–12 fps** (default **8 fps**). A bounded, serial async
  request prevents screenshot requests from piling up. Fast movement is **not
  suppressed**; the cadence is controlled only by your FPS setting.
- **After the pointer stops (~250 ms):** switch to `SCStream` (12fps) on the
  now-fixed crop. Animated content under the stationary cursor continues to
  update. The video output checks `SCFrameStatus` and `dirtyRects` to skip
  decoding and redrawing unchanged frames.
- **When movement resumes:** leave the stationary stream and immediately attempt
  a pointer-centered screenshot, then continue at the configured cadence.
- Pointer coordinates are sampled at ~30Hz independently from screenshot FPS;
  a 1.5-point tolerance suppresses jitter-based mode toggling.
- Zoom 2–12×, pause/resume and screen recording permission UI remain.
  No video is encoded or uploaded.

**Settings:** select **追従FPS設定…**, choose 1–12fps on the slider.
The FPS setting is saved using `UserDefaults` and restored on launch. It
affects only the **moving** phase; stationary streaming remains 12fps.

**Trade-off:** moving screenshots incur more per-request overhead than a
persistent stream. The stationary stream avoids continuously changing
`SCStream.sourceRect`. The design favors clear tracking over aggressive
motion throttling. This is not a measured CPU improvement yet.

## Open in Xcode

1. Open **`CursorMagnifierStream.xcodeproj`** at the repository root.
2. Choose the shared **CursorMagnifierStream** scheme and **My Mac**.
3. Press **Command-R** to compile and run.
4. Grant **Screen Recording** permission and restart the app when macOS asks.

GitHub Actions automatically tests the Xcode project and packages both
`CursorMagnifierStream-arm64.zip` and
`CursorMagnifierStream-Xcode-source.zip` under:
[Cursor Magnifier Stream workflow](../../actions/workflows/cursor-magnifier-stream.yml).
The latter includes both the project and its source tree at correct paths.

The existing CLI build still works:

```bash
bash cursor-magnifier-stream/build.sh
cursor-magnifier-stream/build/CursorMagnifierStream.app/Contents/MacOS/CursorMagnifierStream --self-test
```

## Test coverage and limitations

Actions on `macos-26` can validate both builds, code signing and pure
cursor/coordinate tests. A headless CI session **cannot validate actual screen
capture or responsiveness**, because screen recording permission and an
interactive desktop are required. Test the changeover and frame cadence on
a real Mac. Compare idle/slow/fast movement, streaming a video under a
stationary cursor, and WindowServer CPU to the earlier build.
