import AppKit

// Keep movement cadence separate from the fixed-position SCStream cadence.
extension StreamMagnifierDelegate {
    @objc func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        panel.title = "カーソル追従の設定"
        panel.isReleasedWhenClosed = false
        panel.center()
        let header = NSTextField(labelWithString: "カーソル移動中のキャプチャFPS")
        header.font = .boldSystemFont(ofSize: 14)

        let slider = NSSlider(value: Double(followFPS), minValue: 1, maxValue: 12,
                              target: self, action: #selector(followFPSChanged(_:)))
        slider.numberOfTickMarks = 12
        slider.allowsTickMarkValuesOnly = true
        settingsRateLabel.stringValue = "\(followFPS) fps"
        let sliderRow = row([slider, settingsRateLabel])

        let note = NSTextField(labelWithString:
            "1〜12fpsで追従。約0.25秒静止したら動画（12fps）に切り替えます。")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [header, sliderRow, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        panel.contentView = root
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            sliderRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        settingsWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func followFPSChanged(_ sender: NSSlider) {
        followFPS = max(1, min(12, Int(sender.doubleValue.rounded())))
        sender.doubleValue = Double(followFPS)
        UserDefaults.standard.set(followFPS, forKey: preferenceKey)
        settingsRateLabel.stringValue = "\(followFPS) fps"
        rateLabel.stringValue = "追従 \(followFPS)fps"
    }
}
