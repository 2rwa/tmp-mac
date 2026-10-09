# JPEG Stream Sender — Mac → Android 5.1+

Independent macOS app. **Does not modify or share the old CursorMagnifier executable**.
Sends cropped desktop screenshots around the mouse pointer to the Android app `jpegviewer` in `2rwa/tmp-android`.

## Build and run

Open `JPEGStreamSender.xcodeproj` in Xcode, choose `JPEGStreamSender`, run with ⌘R.
Requirements: macOS 15.2+, Xcode. Approve **Screen Recording** permission; restart the app after approval.
Alternatively run `xcodebuild -project JPEGStreamSender.xcodeproj -scheme JPEGStreamSender -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`.

## Connect

1. On the Mac find its LAN IPv4 address using Network Settings, or `ipconfig getifaddr en0` for Wi-Fi.
2. On the Android 5.1+ phone connect to the Mac address in **JPEG Stream Viewer**.
3. The Mac listens on **TCP 5055**; the Android app is the client. If macOS Firewall prompts, allow incoming connections.
4. Zoom 1–16×, JPEG quality 20–95%, fps 1–20 (target). A 640×360 *logical pixel* viewport is cropped **before** JPEG compression; the Android view scales it up.
5. Sleep / display sleep / session switch suspends the capture. On wake, old captures are ignored and capture resumes after a cooldown.

Protocol: binary `MJP1` + 4-byte big-endian JPEG length + 2-byte normalized cursor X + 2-byte normalized cursor Y + JPEG data.
Coordinates use top-left as origin. The Android client overlays the crosshair rather than baking it into JPEGs.

Only one Android client at a time. Slow-client frames are dropped rather than buffered, though TCP itself can still add latency.

**Security warning:** streamed screenshots are **not encrypted or authenticated**. Only use a trusted local network; do not forward/expose port 5055 publicly.

CI validates the Xcode project, builds an app and runs `--self-test`, then uploads the **complete Xcode source ZIP**. Test screen capture on a physical Mac: hosted runners cannot grant Screen Recording.
