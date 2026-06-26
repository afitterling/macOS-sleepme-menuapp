// Lunair — menu-bar sleep timer for macOS.
// Copyright (C) 2026 Alex Fitterling
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See <https://www.gnu.org/licenses/> for the full text.

import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var sleepTimer: Timer?
    private var countdownTimer: Timer?
    private var sleepDate: Date?
    private var settingsWindow: NSWindow?

    private var currentDuration: TimeInterval?
    private var timerStartDate: Date?
    private var resetCount = 0

    private var runWindow: NSWindow?
    private var nextLabel: NSTextField?
    private var elapsedLabel: NSTextField?
    private var remainingLabel: NSTextField?
    private var resetsLabel: NSTextField?

    // Dimming is done with translucent black overlay windows rather than by
    // changing hardware brightness (the latter needs a private framework the
    // App Sandbox forbids). `dimActivityTimer` polls for user input to lift
    // the dim; `dimFallback` lifts it after a minute regardless.
    private var dimWindows: [NSWindow] = []
    private var dimActivityTimer: Timer?
    private var dimFallback: Timer?

    private let dimDefaultsKey = "dimDisplayWhenSet"
    private var dimWhenSet: Bool {
        get { UserDefaults.standard.bool(forKey: dimDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: dimDefaultsKey) }
    }

    private let resetDefaultsKey = "resetTimerOnActivity"
    private var resetOnActivity: Bool {
        get { UserDefaults.standard.bool(forKey: resetDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: resetDefaultsKey) }
    }

    private let durations: [(label: String, seconds: TimeInterval)] = [
        ("5 minutes",  5 * 60),
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("1 hour",     60 * 60),
        ("2 hours",    2 * 60 * 60),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            let image = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: "Lunair")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeft
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if let sleepDate = sleepDate {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let info = NSMenuItem(title: "Sleeping at \(formatter.string(from: sleepDate))",
                                  action: nil, keyEquivalent: "")
            info.isEnabled = false
            info.image = menuIcon("moon.stars")
            menu.addItem(info)

            let cancel = NSMenuItem(title: "Cancel Timer",
                                    action: #selector(cancelTimer),
                                    keyEquivalent: "")
            cancel.target = self
            cancel.image = menuIcon("xmark.circle")
            menu.addItem(cancel)
            menu.addItem(.separator())
        }

        let sleepNow = NSMenuItem(title: "Sleep Now",
                                  action: #selector(sleepNowAction),
                                  keyEquivalent: "")
        sleepNow.target = self
        sleepNow.image = menuIcon("powersleep")
        menu.addItem(sleepNow)
        menu.addItem(.separator())

        for (label, seconds) in durations {
            let item = NSMenuItem(title: label,
                                  action: #selector(startTimer(_:)),
                                  keyEquivalent: "")
            item.representedObject = seconds
            item.target = self
            item.image = menuIcon("clock")
            menu.addItem(item)
        }

        let custom = NSMenuItem(title: "Custom Time",
                                action: #selector(customTimer),
                                keyEquivalent: "")
        custom.target = self
        custom.image = menuIcon("slider.horizontal.3")
        menu.addItem(custom)

        menu.addItem(.separator())

        let dimNow = NSMenuItem(title: "Bedtime Lightning",
                                action: #selector(dimNowAction),
                                keyEquivalent: "")
        dimNow.target = self
        dimNow.image = menuIcon("moon.zzz")
        menu.addItem(dimNow)

        menu.addItem(.separator())

        let dim = NSMenuItem(title: "Wind Down the Lights When Timer Starts",
                             action: #selector(toggleDim),
                             keyEquivalent: "")
        dim.target = self
        dim.state = dimWhenSet ? .on : .off
        dim.image = menuIcon("moon")
        menu.addItem(dim)

        let reset = NSMenuItem(title: "Reset Timer on Activity",
                               action: #selector(toggleReset),
                               keyEquivalent: "")
        reset.target = self
        reset.state = resetOnActivity ? .on : .off
        reset.image = menuIcon("arrow.clockwise")
        menu.addItem(reset)


        let settings = NSMenuItem(title: "Settings",
                                  action: #selector(showSettings),
                                  keyEquivalent: ",")
        settings.target = self
        settings.image = menuIcon("gearshape")
        menu.addItem(settings)

        menu.addItem(.separator())

        let contact = NSMenuItem(title: "Contact Maintainer",
                                 action: #selector(contactMaintainer),
                                 keyEquivalent: "")
        contact.target = self
        contact.image = menuIcon("envelope")
        menu.addItem(contact)

        let quit = NSMenuItem(title: "Quit",
                              action: #selector(quitAction),
                              keyEquivalent: "q")
        quit.target = self
        quit.image = menuIcon("power")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // Outlined (non-filled) SF Symbol sized for a menu row.
    private func menuIcon(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    @objc private func toggleReset() {
        resetOnActivity.toggle()
        rebuildMenu()
    }

    @objc private func startTimer(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        startTimer(seconds: seconds)
    }

    private func startTimer(seconds: TimeInterval) {
        sleepTimer?.invalidate()
        countdownTimer?.invalidate()

        currentDuration = seconds
        timerStartDate = Date()
        resetCount = 0
        sleepDate = Date().addingTimeInterval(seconds)

        sleepTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.sleepNow()
        }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.handleTick()
        }
        updateTitle()
        rebuildMenu()

        if dimWhenSet {
            // Wind the lights down to 10% as soon as the timer starts. The
            // countdown keeps running, and brightness restores on mouse move
            // or after 1m.
            dimScreen(to: setDimBrightness)
        }
    }

    private func handleTick() {
        // If the user has been active since the last tick, push the deadline
        // back out to a full duration so the Mac only sleeps after real idle.
        if resetOnActivity, let duration = currentDuration, systemIdleSeconds() < 2 {
            sleepDate = Date().addingTimeInterval(duration)
            resetCount += 1
            sleepTimer?.invalidate()
            sleepTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.sleepNow()
            }
        }
        updateTitle()
        updateRunWindow()
    }

    private func systemIdleSeconds() -> CFTimeInterval {
        // Seconds since the last keyboard/mouse input. Needs no special
        // permission, unlike a global event monitor.
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func updateTitle() {
        guard let sleepDate = sleepDate else {
            statusItem.button?.title = ""
            return
        }
        let remaining = max(0, Int(sleepDate.timeIntervalSinceNow.rounded()))
        let h = remaining / 3600
        let m = (remaining % 3600) / 60
        let s = remaining % 60
        if h > 0 {
            statusItem.button?.title = String(format: " %d:%02d:%02d", h, m, s)
        } else {
            statusItem.button?.title = String(format: " %d:%02d", m, s)
        }
    }

    // MARK: - Running-timer popup

    private func showRunWindow() {
        if runWindow == nil { runWindow = makeRunWindow() }
        updateRunWindow()
        NSApp.activate(ignoringOtherApps: true)
        runWindow?.center()
        runWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeRunWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Sleep Timer"
        window.isReleasedWhenClosed = false
        window.level = .floating

        let next = makeLabel("", font: .systemFont(ofSize: 13, weight: .semibold),
                             color: .controlAccentColor)
        let elapsed = makeLabel("", font: .monospacedDigitSystemFont(ofSize: 13, weight: .regular),
                                color: .labelColor)
        let remaining = makeLabel("", font: .monospacedDigitSystemFont(ofSize: 24, weight: .semibold),
                                  color: .labelColor)
        let resets = makeLabel("", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        nextLabel = next
        elapsedLabel = elapsed
        remainingLabel = remaining
        resetsLabel = resets

        let stack = NSStackView(views: [
            next,
            remaining,
            elapsed,
            resets,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ])
        }
        return window
    }

    private func updateRunWindow() {
        guard let window = runWindow, window.isVisible else { return }
        if let sleepDate = sleepDate {
            remainingLabel?.stringValue = clock(Int(sleepDate.timeIntervalSinceNow.rounded()))
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            nextLabel?.stringValue = "Next: Sleep at \(formatter.string(from: sleepDate))"
        }
        if let start = timerStartDate {
            elapsedLabel?.stringValue = "Elapsed: " + clock(Int(Date().timeIntervalSince(start).rounded()))
        }
        resetsLabel?.stringValue = "Resets: \(resetCount)"
    }

    private func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    @objc private func cancelTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        sleepDate = nil
        currentDuration = nil
        timerStartDate = nil
        resetCount = 0
        statusItem.button?.title = ""
        runWindow?.orderOut(nil)
        rebuildMenu()
    }

    @objc private func dimNowAction() {
        dimScreen(to: windDownBrightness)
    }

    @objc private func sleepNowAction() {
        sleepNow()
    }

    private func sleepNow() {
        sleepTheMac()
        cancelTimer()
    }

    // The App Sandbox forbids launching `pmset`, and macOS exposes no public
    // sandbox-safe call to sleep the Mac. We drive System Events over Apple
    // events instead — allowed by the apple-events temporary exception in the
    // entitlements, gated behind a one-time Automation permission prompt.
    private func sleepTheMac() {
        let source = "tell application \"System Events\" to sleep"
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
        }
        if let error = error {
            // -1743 is errAEEventNotPermitted: the user declined Automation
            // access for System Events. Point them at the fix rather than
            // failing silently.
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
                warn("Lunair needs permission to control System Events to sleep "
                   + "your Mac. Grant it in System Settings ▸ Privacy & Security "
                   + "▸ Automation, then try again.")
            }
        }
    }

    // MARK: - Dimming

    // The screen is dimmed by floating translucent black windows over every
    // display. Values are expressed as a target perceived brightness so the
    // call sites read the same as the old hardware-brightness code: winding
    // down lands at 30%, the "dim when timer set" toggle goes lower, to 10%.
    private let windDownBrightness: Float = 0.30
    private let setDimBrightness: Float = 0.10

    // How long the dim has been up; used to ignore the input that triggered it.
    private let dimGrace: TimeInterval = 2

    // Show (or re-target) the dim overlay, then lift it on the next user input
    // after a short grace period — or after a minute, whichever comes first.
    private func dimScreen(to brightness: Float) {
        let alpha = CGFloat(1 - min(max(brightness, 0), 1))
        showDimOverlay(alpha: alpha)
        armDimRestore()
        dimFallback?.invalidate()
        dimFallback = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            self?.restoreBrightness()
        }
    }

    private func showDimOverlay(alpha: CGFloat) {
        if dimWindows.isEmpty {
            for screen in NSScreen.screens {
                let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                                      backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.backgroundColor = .black
                window.isOpaque = false
                window.hasShadow = false
                window.ignoresMouseEvents = true       // purely visual; never steals input
                window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
                window.orderFrontRegardless()
                dimWindows.append(window)
            }
        }
        for window in dimWindows { window.alphaValue = alpha }
    }

    // Poll for input rather than installing a global event monitor (the App
    // Sandbox forbids the latter). `systemIdleSeconds()` resets to ~0 on any
    // keyboard/mouse activity and needs no special permission.
    private func armDimRestore() {
        dimActivityTimer?.invalidate()
        let armedAt = Date()
        dimActivityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Wait out the grace window so the click that dimmed the screen
            // doesn't immediately lift it.
            guard Date().timeIntervalSince(armedAt) > self.dimGrace else { return }
            if self.systemIdleSeconds() < 1 { self.restoreBrightness() }
        }
    }

    private func restoreBrightness() {
        dimFallback?.invalidate()
        dimFallback = nil
        dimActivityTimer?.invalidate()
        dimActivityTimer = nil
        for window in dimWindows { window.orderOut(nil) }
        dimWindows.removeAll()
    }

    @objc private func toggleDim() {
        dimWhenSet.toggle()
        rebuildMenu()
    }

    // MARK: - Custom timer

    @objc private func customTimer() {
        let alert = NSAlert()
        alert.messageText = "Custom Timer"
        alert.informativeText = "Sleep after how many minutes?"
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "Minutes"
        field.alignment = .left
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let minutes = Double(trimmed), minutes > 0 else { return }
        startTimer(seconds: minutes * 60)
    }

    private func warn(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Settings

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.center()
    }

    private func makeSettingsWindow() -> NSWindow {
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String ?? "Sleep Timer"
        let bundleID = Bundle.main.bundleIdentifier ?? "—"
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false

        let branding = NSMutableAttributedString(
            string: name + " ",
            attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .heavy),
                         .foregroundColor: NSColor.labelColor])
        branding.append(NSAttributedString(
            string: "(a Sleep Timer by sp33c.tech)",
            attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .regular),
                         .foregroundColor: NSColor.secondaryLabelColor]))
        let titleLabel = NSTextField(labelWithAttributedString: branding)
        let rows = NSStackView(views: [
            settingRow("Bundle Identifier", bundleID),
            settingRow("Version", version),
            settingRow("Build", build),
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8

        let stack = NSStackView(views: [titleLabel, rows])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                stack.topAnchor.constraint(equalTo: content.topAnchor),
            ])
        }
        return window
    }

    private func settingRow(_ label: String, _ value: String) -> NSView {
        let key = makeLabel(label + ":", font: .systemFont(ofSize: 12),
                            color: .secondaryLabelColor)
        let val = makeLabel(value, font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                            color: .labelColor)
        val.isSelectable = true
        let row = NSStackView(views: [key, val])
        row.orientation = .horizontal
        row.spacing = 6
        return row
    }

    private func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        return label
    }

    @objc private func contactMaintainer() {
        if let url = URL(string: "https://sleeptimer.sp33c.tech/support") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}

// Program entry. We're on the main thread at launch, so it's safe to assume
// the main actor for the @MainActor-isolated AppDelegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
