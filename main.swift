// Lunis — menu-bar sleep timer for macOS.
// Copyright (C) 2026 Alex Fitterling
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See <https://www.gnu.org/licenses/> for the full text.

import Cocoa
import ServiceManagement

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
            let image = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: "Lunis")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeft
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        }
        rebuildMenu()

        // Surface the Automation consent prompt now rather than when a timer
        // fires. Deferred so it doesn't block launch.
        DispatchQueue.main.async { [weak self] in self?.requestAutomationPermission() }
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

        let dimNow = NSMenuItem(title: "Bedtime Lighting",
                                action: #selector(dimNowAction),
                                keyEquivalent: "")
        dimNow.target = self
        dimNow.image = menuIcon("moon.zzz")
        // Checkmark while the manual dim is active; selecting it again lifts it.
        dimNow.state = (dimIsManual && !dimWindows.isEmpty) ? .on : .off
        menu.addItem(dimNow)

        menu.addItem(.separator())

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
            // Wind the lights down as soon as the timer starts. The countdown
            // keeps running, and brightness restores on activity or after 1m.
            dimScreen(to: dimBrightness)
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
        // Seconds since the last user input. Needs no special permission,
        // unlike a global event monitor. kCGAnyInputEventType (~0) misses
        // system-defined events — hardware brightness/media keys — so fold
        // those in separately: pressing brightness-up while the dim overlay is
        // showing must count as activity and lift the dim (verified: type 14
        // resets on brightness keys while ~0 does not).
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        let sysDefined = CGEventType(rawValue: 14) ?? .null   // NX_SYSDEFINED
        return min(
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: sysDefined))
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

    // Bedtime Lighting: a manual, persistent reading light. Toggles from the
    // menu. Deliberately disconnected from the automatic timer dim: it does NOT
    // lift on mouse/keyboard activity and has no auto-lift timeout.
    @objc private func dimNowAction() {
        if dimIsManual, !dimWindows.isEmpty {
            restoreBrightness()
        } else {
            dimScreen(to: bedtimeLightBrightness, manual: true)
        }
        rebuildMenu()
    }

    @objc private func sleepNowAction() {
        sleepNow()
    }

    private func sleepNow() {
        sleepTheMac()
        cancelTimer()
    }

    // The App Sandbox exposes no public call to sleep the Mac, so we drive
    // System Events over Apple events. Two independent gates must both pass:
    // (1) the sandbox blocks outgoing Apple events unless the
    //     temporary-exception.apple-events entitlement lists the target, and
    // (2) TCC still requires per-user Automation consent (the one-time prompt;
    //     revocable in System Settings ▸ Privacy & Security ▸ Automation).
    // The raw kAESleep power event is not an alternative: it hits gate (1) with
    // no entitlement that can authorize it.
    private func sleepTheMac() {
        let source = "tell application \"System Events\" to sleep"
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
        }
        if let error = error {
            NSLog("Lunis: sleep failed — %@", error)
            // -1743 is errAEEventNotPermitted: Automation consent is missing
            // or was declined. Guide the user to the fix instead of failing
            // silently.
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
                guideToAutomationSettings()
            }
        }
    }

    // MARK: - Automation permission

    // Trigger the one-time Automation consent prompt at first launch, so the
    // user grants it while they're setting up — not hours later when a timer
    // fires into a silent failure. Only actually sending an Apple event makes
    // TCC show the prompt (and list Lunis under Privacy ▸ Automation), so we
    // send a harmless read of System Events' name and ignore the result. If
    // consent was previously declined (-1743), walk the user to the setting.
    private func requestAutomationPermission() {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"System Events\" to get name")?
            .executeAndReturnError(&error)
        if let error = error,
           (error[NSAppleScript.errorNumber] as? Int) == -1743 {
            guideToAutomationSettings()
        }
    }

    // Explain why the permission is needed and open the exact settings pane.
    private func guideToAutomationSettings() {
        let alert = NSAlert()
        alert.messageText = "Allow Lunis to sleep your Mac"
        alert.informativeText =
            "Lunis puts your Mac to sleep by asking System Events, which needs "
          + "your permission.\n\nOpen System Settings ▸ Privacy & Security ▸ "
          + "Automation, then turn on “System Events” under Lunis."
        alert.addButton(withTitle: "Open Automation Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Dimming

    // The screen is dimmed by floating translucent black windows over every
    // display. `dimBrightness` is the target perceived brightness the overlay
    // dims to (0 = black, 1 = no dim), configurable from Settings.
    private let dimBrightnessKey = "dimBrightness"
    private var dimBrightness: Float {
        get {
            UserDefaults.standard.object(forKey: dimBrightnessKey) == nil
                ? 0.15 : UserDefaults.standard.float(forKey: dimBrightnessKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: dimBrightnessKey) }
    }

    // Bedtime Lighting has its own light level, independent of the timer dim.
    private let bedtimeLightKey = "bedtimeLightBrightness"
    private var bedtimeLightBrightness: Float {
        get {
            UserDefaults.standard.object(forKey: bedtimeLightKey) == nil
                ? 0.15 : UserDefaults.standard.float(forKey: bedtimeLightKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: bedtimeLightKey) }
    }

    // How long the dim has been up; used to ignore the input that triggered it.
    private let dimGrace: TimeInterval = 2

    // Two disconnected dim features share the overlay plumbing:
    //  - automatic timer dim (manual: false): lifts on any user activity after
    //    the grace period, or after a minute, whichever comes first;
    //  - manual Bedtime Lighting (manual: true): a persistent reading light —
    //    survives mouse/keyboard use, has no timeout, and lifts only on the
    //    hardware brightness keys or by toggling the menu item again.
    private var dimIsManual = false

    private func dimScreen(to brightness: Float, manual: Bool = false) {
        dimIsManual = manual
        let alpha = CGFloat(1 - min(max(brightness, 0), 1))
        showDimOverlay(alpha: alpha)
        armDimRestore()
        dimFallback?.invalidate()
        dimFallback = nil
        if !manual {
            dimFallback = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                self?.restoreBrightness()
            }
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
    // Sandbox forbids the latter). The idle counters reset to ~0 on activity
    // and need no special permission. Automatic dims lift on any input; the
    // manual Bedtime Lighting only on the brightness/media keys.
    private func armDimRestore() {
        dimActivityTimer?.invalidate()
        let armedAt = Date()
        dimActivityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Wait out the grace window so the click that dimmed the screen
            // doesn't immediately lift it.
            guard Date().timeIntervalSince(armedAt) > self.dimGrace else { return }
            let idle = self.dimIsManual
                ? self.brightnessKeyIdleSeconds()
                : self.systemIdleSeconds()
            if idle < 1 { self.restoreBrightness() }
        }
    }

    // Seconds since the last system-defined event (hardware brightness/media
    // keys) — the only input that lifts the manual Bedtime Lighting.
    private func brightnessKeyIdleSeconds() -> CFTimeInterval {
        let sysDefined = CGEventType(rawValue: 14) ?? .null   // NX_SYSDEFINED
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                       eventType: sysDefined)
    }

    private func restoreBrightness() {
        dimFallback?.invalidate()
        dimFallback = nil
        dimActivityTimer?.invalidate()
        dimActivityTimer = nil
        for window in dimWindows { window.orderOut(nil) }
        dimWindows.removeAll()
        dimIsManual = false
        rebuildMenu()   // clear the Bedtime Lighting checkmark
    }

    // MARK: - Settings controls

    // Login item registration. SMAppService is the sandbox-safe, macOS 13+ way
    // to launch at login; it registers reliably only for a signed app bundle.
    private var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Lunis: launch-at-login toggle failed — \(error)")
            }
        }
    }

    @objc private func setLaunchAtLogin(_ sender: NSButton) {
        launchAtLogin = (sender.state == .on)
        // Reflect what actually took effect in case registration failed.
        sender.state = launchAtLogin ? .on : .off
    }

    @objc private func setDimWhenSet(_ sender: NSButton) {
        dimWhenSet = (sender.state == .on)
    }

    @objc private func setResetOnActivity(_ sender: NSButton) {
        resetOnActivity = (sender.state == .on)
    }

    @objc private func dimLevelChanged(_ sender: NSSlider) {
        dimBrightness = sender.floatValue
        // Live-update the overlay only if the automatic timer dim is showing.
        if !dimWindows.isEmpty, !dimIsManual {
            let alpha = CGFloat(1 - min(max(sender.floatValue, 0), 1))
            for window in dimWindows { window.alphaValue = alpha }
        }
    }

    @objc private func bedtimeLevelChanged(_ sender: NSSlider) {
        bedtimeLightBrightness = sender.floatValue
        // Live-update the overlay only if Bedtime Lighting is currently on.
        if !dimWindows.isEmpty, dimIsManual {
            let alpha = CGFloat(1 - min(max(sender.floatValue, 0), 1))
            for window in dimWindows { window.alphaValue = alpha }
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
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

        // Preferences — checkboxes plus the timer dim-level slider.
        let launch = makeCheckbox("Launch at login",
                                  on: launchAtLogin, action: #selector(setLaunchAtLogin(_:)))
        let windDown = makeCheckbox("Wind down the lights when the timer starts",
                                    on: dimWhenSet, action: #selector(setDimWhenSet(_:)))
        let resetActivity = makeCheckbox("Reset timer on activity",
                                         on: resetOnActivity, action: #selector(setResetOnActivity(_:)))

        let dimRow = sliderRow(caption: "Dim level",
                               value: dimBrightness,
                               action: #selector(dimLevelChanged(_:)))

        let prefs = NSStackView(views: [launch, windDown, resetActivity, dimRow])
        prefs.orientation = .vertical
        prefs.alignment = .leading
        prefs.spacing = 8

        // Bedtime Lighting — its own section: a persistent reading light,
        // separate from the timer dim. Lifts on brightness keys or via the
        // menu toggle.
        let bedtimeHeader = makeLabel("Bedtime Lighting",
                                      font: .systemFont(ofSize: 13, weight: .semibold),
                                      color: .labelColor)
        let bedtimeHint = makeLabel(
            "Persistent reading light. Turn off with the brightness keys\n"
          + "or by choosing Bedtime Lighting again from the menu.",
            font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        let bedtimeRow = sliderRow(caption: "Light level",
                                   value: bedtimeLightBrightness,
                                   action: #selector(bedtimeLevelChanged(_:)))
        let bedtime = NSStackView(views: [bedtimeHeader, bedtimeHint, bedtimeRow])
        bedtime.orientation = .vertical
        bedtime.alignment = .leading
        bedtime.spacing = 8

        let rows = NSStackView(views: [
            settingRow("Bundle Identifier", bundleID),
            settingRow("Version", version),
            settingRow("Build", build),
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8

        let stack = NSStackView(views: [titleLabel, prefs, makeSeparator(),
                                        bedtime, makeSeparator(), rows])
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
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
            // Size the window to the stack's natural height so nothing is
            // clipped; the stack's edgeInsets provide the bottom padding.
            content.layoutSubtreeIfNeeded()
            window.setContentSize(content.fittingSize)
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

    // A captioned brightness slider row (0 = black … 0.7 = mild dim).
    private func sliderRow(caption: String, value: Float, action: Selector) -> NSStackView {
        let label = makeLabel(caption, font: .systemFont(ofSize: 12),
                              color: .secondaryLabelColor)
        let slider = NSSlider(value: Double(value), minValue: 0.0, maxValue: 0.7,
                              target: self, action: action)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let row = NSStackView(views: [label, slider])
        row.orientation = .horizontal
        row.spacing = 10
        return row
    }

    private func makeCheckbox(_ title: String, on: Bool, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = on ? .on : .off
        return button
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 320).isActive = true
        return box
    }

    @objc private func contactMaintainer() {
        if let url = URL(string: "https://lunis.sp33c.tech/support") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}

#if APP_STORE
// Paid, up-front App Store app: require a Mac App Store receipt. If one isn't
// present, exit(173) so macOS fetches a fresh receipt (and refuses to run
// copies that were never purchased). Gated to the App Store build so the
// Developer ID build and Xcode debug runs — which have no receipt — still run.
if (try? Bundle.main.appStoreReceiptURL?.checkResourceIsReachable()) != true {
    exit(173)
}
#endif

// Program entry. We're on the main thread at launch, so it's safe to assume
// the main actor for the @MainActor-isolated AppDelegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
