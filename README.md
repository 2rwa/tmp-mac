# tmp-mac: macOS 26 Apple Silicon environment probe

The GitHub Actions workflow automatically runs on a push to main and can be manually run using **workflow_dispatch**. It uses the standard M1/arm64 `macos-26` runner.

Tests: OS/CPU/RAM/GPU inventory; native Metal device and command buffer; native Safari version and graphical desktop capture; Playwright Chromium and WebKit launch/screenshots; native Safari WebDriver best-effort launch/screenshot; WebGL2; WebGPU WGSL compute and triangle render.

See the **job summary** and download the `macos-26-m1-probe` artifact to inspect `report.md`, `results.json`, environment logs and browser screenshots.

The macOS hosted runner may not expose a usable desktop session or Metal acceleration. Native Safari.app, Chromium, and Playwright WebKit are recorded separately so unsupported features are not confused with working hardware GPU.

## macOS utilities

- [Cursor Magnifier](cursor-magnifier/README.md): Swift/AppKit tool that magnifies the desktop around the pointer (macOS 15.2+, Xcode project included).
- [Input Method Status](README-Xcode.md): inspect the active input method in a native macOS window.
