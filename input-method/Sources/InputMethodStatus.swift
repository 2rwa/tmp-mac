import AppKit
import Carbon
import Darwin

// Only public Text Input Source Services APIs are used.
// No key logging or Accessibility permission is required.
private struct InputSourceInfo: Equatable {
    let name: String
    let identifier: String
    let modeIdentifier: String
    let type: String
    let languages: String
    let enabled: String
    let selected: String
    let asciiCapable: String

    func describe(_ title: String) -> String {
        """
        ■ \(title)
          表示名             : \(name)
          Input Source ID    : \(identifier)
          Input Mode ID      : \(modeIdentifier)
          種類               : \(type)
          言語               : \(languages)
          有効               : \(enabled)
          選択中             : \(selected)
          ASCII 対応         : \(asciiCapable)
        """
    }
}

private struct InputSourceSnapshot: Equatable {
    let selected: InputSourceInfo?
    let layout: InputSourceInfo?
    let ascii: InputSourceInfo?

    var summary: String {
        guard let selected else { return "入力ソースを取得できません" }
        let mode = selected.modeIdentifier == "—" ? "" : " / \(selected.modeIdentifier)"
        return "\(selected.name) / \(selected.identifier)\(mode)"
    }

    var report: String {
        let sections: [(String, InputSourceInfo?)] = [
            ("現在選択されている入力ソース", selected),
            ("現在のキーボードレイアウト", layout),
            ("ASCII 入力可能な入力ソース", ascii)
        ]
        return sections.map { title, info in
            info?.describe(title) ?? "■ \(title)\n  (取得できません)"
        }.joined(separator: "\n\n")
        + "\n\n※ キー入力・変換中の文字列・候補ウィンドウの内容は取得しません。"
    }
}

private enum TISReader {
    static func string(_ source: TISInputSource, key: CFString) -> String {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return "—" }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    static func languages(_ source: TISInputSource) -> String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return "—"
        }
        let array = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as NSArray
        let values = array.compactMap { $0 as? String }
        return values.isEmpty ? "—" : values.joined(separator: ", ")
    }

    static func boolean(_ source: TISInputSource, key: CFString) -> String {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return "—" }
        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(value) ? "true" : "false"
    }

    static func info(_ source: TISInputSource?) -> InputSourceInfo? {
        guard let source else { return nil }
        return InputSourceInfo(
            name: string(source, key: kTISPropertyLocalizedName),
            identifier: string(source, key: kTISPropertyInputSourceID),
            modeIdentifier: string(source, key: kTISPropertyInputModeID),
            type: string(source, key: kTISPropertyInputSourceType),
            languages: languages(source),
            enabled: boolean(source, key: kTISPropertyInputSourceIsEnabled),
            selected: boolean(source, key: kTISPropertyInputSourceIsSelected),
            asciiCapable: boolean(source, key: kTISPropertyInputSourceIsASCIICapable)
        )
    }

    static func capture() -> InputSourceSnapshot {
        InputSourceSnapshot(
            selected: info(TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()),
            layout: info(TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()),
            ascii: info(TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue())
        )
    }
}

@MainActor
private final class InputMethodAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let statusLabel = NSTextField(labelWithString: "取得中…")
    private let updatedLabel = NSTextField(labelWithString: "")
    private let details = NSTextView(frame: NSRect(x: 0, y: 0, width: 730, height: 390))
    private let testField = NSTextField(string: "")
    private var previous: InputSourceSnapshot?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 570),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Input Method Status"
        window.center()
        window.minSize = NSSize(width: 630, height: 470)
        self.window = window

        let title = NSTextField(labelWithString: "macOS 入力ソース・モニター")
        title.font = .boldSystemFont(ofSize: 20)
        let refreshButton = NSButton(title: "更新", target: self, action: #selector(refreshClicked))
        let copyButton = NSButton(title: "情報をコピー", target: self, action: #selector(copyClicked))
        let header = NSStackView(views: [title, refreshButton, copyButton])
        header.orientation = .horizontal
        header.spacing = 12

        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        updatedLabel.font = .systemFont(ofSize: 11)
        updatedLabel.textColor = .secondaryLabelColor
        let testLabel = NSTextField(labelWithString: "入力テスト（ここで「あ / A」を切り替え）")
        testLabel.font = .systemFont(ofSize: 12)
        testField.placeholderString = "日本語・英語を入力して IME を切り替える"
        testField.font = .systemFont(ofSize: 14)

        details.isEditable = false
        details.isSelectable = true
        details.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        details.textContainerInset = NSSize(width: 12, height: 12)
        details.isVerticallyResizable = true
        details.autoresizingMask = [.width]
        details.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.documentView = details

        let content = NSStackView(views: [header, statusLabel, updatedLabel, testLabel, testField, scroll])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 11
        content.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        window.contentView = root
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            header.widthAnchor.constraint(equalTo: content.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
            updatedLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
            testLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
            testField.widthAnchor.constraint(equalTo: content.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: content.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 270)
        ])

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(testField)
        refresh(force: true)

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged(_:)),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        timer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        if CommandLine.arguments.contains("--window-smoke") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { NSApp.terminate(nil) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func inputSourceChanged(_ notification: Notification) { refresh(force: false) }
    @objc private func poll() { refresh(force: false) }
    @objc private func refreshClicked() { refresh(force: true) }
    @objc private func copyClicked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details.string, forType: .string)
    }

    private func refresh(force: Bool) {
        let snapshot = TISReader.capture()
        guard force || snapshot != previous else { return }
        previous = snapshot
        statusLabel.stringValue = snapshot.summary
        details.string = snapshot.report
        updatedLabel.stringValue = "最終更新: \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)) / 通知 + 0.5秒監視"
    }
}

private func selfTest() -> Bool {
    let sample = InputSourceInfo(name: "日本語", identifier: "example.japanese",
        modeIdentifier: "example.hiragana", type: "example.type",
        languages: "ja", enabled: "true", selected: "true", asciiCapable: "false")
    let snapshot = InputSourceSnapshot(selected: sample, layout: nil, ascii: nil)
    return snapshot.summary.contains("example.hiragana")
        && snapshot.report.contains("Input Source ID    : example.japanese")
        && snapshot.report.contains("現在のキーボードレイアウト")
        && snapshot.report.contains("(取得できません)")
}

if CommandLine.arguments.contains("--self-test") {
    guard selfTest() else { fputs("FAIL: snapshot formatting\n", stderr); exit(1) }
    print("PASS: snapshot formatting and missing-source fallback")
} else if CommandLine.arguments.contains("--dump") {
    print(TISReader.capture().report)
} else {
    // The initial entry point is the process's main thread.
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = InputMethodAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
