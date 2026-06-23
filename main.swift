// SleepTimer — menu-bar sleep timer for macOS.
// Copyright (C) 2026 Alex Fitterling
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See <https://www.gnu.org/licenses/> for the full text.

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var sleepTimer: Timer?
    private var countdownTimer: Timer?
    private var sleepDate: Date?
    private var settingsWindow: NSWindow?

    private var currentDuration: TimeInterval?
    private var timerStartDate: Date?
    private var resetCount = 0
    private var pendingDimOnly = false

    private var runWindow: NSWindow?
    private var nextLabel: NSTextField?
    private var elapsedLabel: NSTextField?
    private var remainingLabel: NSTextField?
    private var resetsLabel: NSTextField?

    private var savedBrightness: Float?
    private var brightnessMonitor: Any?
    private var brightnessFallback: Timer?

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

    private let stopMusicDefaultsKey = "stopMusicWhenAsleep"
    private var stopMusicWhenAsleep: Bool {
        get { UserDefaults.standard.bool(forKey: stopMusicDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: stopMusicDefaultsKey) }
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
            let image = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: "Sleep Timer")?
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

        let titleItem = NSMenuItem(title: "BedTime", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        let title = NSMutableAttributedString(
            string: "BedTime ",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize + 1, weight: .heavy)])
        title.append(NSAttributedString(
            string: "(a Sleep Timer by sp33c.tech)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        titleItem.attributedTitle = title
        menu.addItem(titleItem)
        menu.addItem(.separator())

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

        let custom = NSMenuItem(title: "Custom…",
                                action: #selector(customTimer),
                                keyEquivalent: "")
        custom.target = self
        custom.image = menuIcon("slider.horizontal.3")
        menu.addItem(custom)

        let schedule = NSMenuItem(title: "Schedule a Time…",
                                  action: #selector(scheduleTime),
                                  keyEquivalent: "")
        schedule.target = self
        schedule.image = menuIcon("calendar")
        menu.addItem(schedule)

        menu.addItem(.separator())

        let dimNow = NSMenuItem(title: "Bedtime Lightning",
                                action: #selector(dimNowAction),
                                keyEquivalent: "")
        dimNow.target = self
        dimNow.image = menuIcon("moon.zzz")
        menu.addItem(dimNow)

        menu.addItem(.separator())

        let dim = NSMenuItem(title: "Dim Screen to 10% When Timer Set",
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

        let stopMusic = NSMenuItem(title: "Stop Music When I Fall Asleep",
                                   action: #selector(toggleStopMusic),
                                   keyEquivalent: "")
        stopMusic.target = self
        stopMusic.state = stopMusicWhenAsleep ? .on : .off
        stopMusic.image = menuIcon("pause.circle")
        menu.addItem(stopMusic)

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(showSettings),
                                  keyEquivalent: ",")
        settings.target = self
        settings.image = menuIcon("gearshape")
        menu.addItem(settings)

        menu.addItem(.separator())

        let contact = NSMenuItem(title: "Contact Maintainer",
                                 action: nil,
                                 keyEquivalent: "")
        contact.isEnabled = false
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

    private func startTimer(seconds: TimeInterval, dimOnly: Bool = false) {
        sleepTimer?.invalidate()
        countdownTimer?.invalidate()

        currentDuration = seconds
        timerStartDate = Date()
        resetCount = 0
        pendingDimOnly = dimOnly
        sleepDate = Date().addingTimeInterval(seconds)

        sleepTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            if dimOnly {
                self?.iWantToSleep()
                self?.cancelTimer()
            } else {
                self?.sleepNow()
            }
        }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.handleTick()
        }
        updateTitle()
        rebuildMenu()
        showRunWindow()

        if dimWhenSet {
            // Dim the screen to 10% as soon as a timer starts. The countdown
            // keeps running, and brightness restores on mouse move or after 1m.
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
            let action = pendingDimOnly ? "Dim to 30%" : "Sleep"
            nextLabel?.stringValue = "Next: \(action) at \(formatter.string(from: sleepDate))"
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
        if stopMusicWhenAsleep { pauseMusic() }
        runPmset(["sleepnow"])
        cancelTimer()
    }

    private func runPmset(_ arguments: [String]) {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = arguments
        try? task.run()
    }

    // MARK: - Brightness

    // "Sleep Time" winds the screen down to 30%; the "dim when timer set"
    // toggle takes it lower, to 10%.
    private let windDownBrightness: Float = 0.30
    private let setDimBrightness: Float = 0.10

    @objc private func iWantToSleep() {
        dimScreen(to: windDownBrightness)
    }

    // Remember the current brightness, dim, then restore it the next time the
    // user moves the mouse (after a short grace period so the click that
    // triggered the dim doesn't immediately undo it).
    private func dimScreen(to value: Float) {
        if savedBrightness == nil { savedBrightness = currentDisplayBrightness() }
        setDisplayBrightness(value)
        armBrightnessRestore()
        // Fall back to the original brightness after a minute even if the user
        // never moves the mouse.
        brightnessFallback?.invalidate()
        brightnessFallback = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            self?.restoreBrightness()
        }
    }

    private func armBrightnessRestore() {
        if let monitor = brightnessMonitor {
            NSEvent.removeMonitor(monitor)
            brightnessMonitor = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.savedBrightness != nil else { return }
            self.brightnessMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
            ) { [weak self] _ in
                self?.restoreBrightness()
            }
        }
    }

    private func restoreBrightness() {
        brightnessFallback?.invalidate()
        brightnessFallback = nil
        if let monitor = brightnessMonitor {
            NSEvent.removeMonitor(monitor)
            brightnessMonitor = nil
        }
        guard let saved = savedBrightness else { return }
        setDisplayBrightness(saved)
        savedBrightness = nil
    }

    private func currentDisplayBrightness() -> Float {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW) else { return windDownBrightness }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return windDownBrightness }
        typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let getBrightness = unsafeBitCast(sym, to: GetBrightness.self)
        var value: Float = windDownBrightness
        _ = getBrightness(CGMainDisplayID(), &value)
        return value
    }

    private func setDisplayBrightness(_ value: Float) {
        // DisplayServices is private but works across Intel and Apple Silicon
        // without the accessibility permission a key-event approach would need.
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return }
        typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let setBrightness = unsafeBitCast(sym, to: SetBrightness.self)

        let clamped = min(max(value, 0), 1)
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let number = screen.deviceDescription[key] as? NSNumber {
                _ = setBrightness(number.uint32Value, clamped)
            }
        }
    }

    @objc private func toggleDim() {
        dimWhenSet.toggle()
        rebuildMenu()
    }

    @objc private func toggleStopMusic() {
        stopMusicWhenAsleep.toggle()
        rebuildMenu()
    }

    // Pause whatever is playing in Music and Spotify. Pausing an app that is
    // already paused (or not running) is a harmless no-op. macOS prompts once
    // for Automation permission the first time this runs.
    private func pauseMusic() {
        let script = """
        tell application "System Events"
            if (name of processes) contains "Music" then tell application "Music" to pause
            if (name of processes) contains "Spotify" then tell application "Spotify" to pause
        end tell
        """
        if let apple = NSAppleScript(source: script) {
            var error: NSDictionary?
            apple.executeAndReturnError(&error)
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

    @objc private func scheduleTime() {
        let alert = NSAlert()
        alert.messageText = "Schedule a Time"
        alert.informativeText = "Sleep at what time? (e.g. 23:30 or 11:30 PM)"
        alert.addButton(withTitle: "Schedule")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "HH:mm"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let target = nextDate(matching: trimmed) else {
            warn("Couldn't read that time. Try a format like 23:30 or 11:30 PM.")
            return
        }
        // At the scheduled time, wind the display down to 30% rather than
        // sleeping the Mac outright.
        startTimer(seconds: target.timeIntervalSinceNow, dimOnly: true)
    }

    // Parse a clock time and return the next future Date that matches it,
    // rolling over to tomorrow if the time has already passed today.
    private func nextDate(matching text: String) -> Date? {
        let formats = ["HH:mm", "H:mm", "h:mm a", "h a", "ha"]
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        var components: DateComponents?
        for format in formats {
            parser.dateFormat = format
            if let date = parser.date(from: text) {
                components = Calendar.current.dateComponents([.hour, .minute], from: date)
                break
            }
        }
        guard let comps = components else { return nil }
        let calendar = Calendar.current
        guard let next = calendar.nextDate(after: Date(), matching: comps,
                                           matchingPolicy: .nextTime) else { return nil }
        return next
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

        let titleLabel = makeLabel(name, font: .boldSystemFont(ofSize: 15),
                                   color: .labelColor)
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

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
