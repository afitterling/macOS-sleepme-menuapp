import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var sleepTimer: Timer?
    private var countdownTimer: Timer?
    private var sleepDate: Date?

    private let durations: [(label: String, seconds: TimeInterval)] = [
        ("5 minutes",  5 * 60),
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("1 hour",     60 * 60),
        ("2 hours",    2 * 60 * 60),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "💤"
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
            menu.addItem(info)

            let cancel = NSMenuItem(title: "Cancel Timer",
                                    action: #selector(cancelTimer),
                                    keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
            menu.addItem(.separator())
        }

        for (label, seconds) in durations {
            let item = NSMenuItem(title: label,
                                  action: #selector(startTimer(_:)),
                                  keyEquivalent: "")
            item.representedObject = seconds
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let sleepNow = NSMenuItem(title: "Sleep Now",
                                  action: #selector(sleepNowAction),
                                  keyEquivalent: "")
        sleepNow.target = self
        menu.addItem(sleepNow)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit",
                              action: #selector(quitAction),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func startTimer(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }

        sleepTimer?.invalidate()
        countdownTimer?.invalidate()

        sleepDate = Date().addingTimeInterval(seconds)

        sleepTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.sleepNow()
        }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTitle()
        }
        updateTitle()
        rebuildMenu()
    }

    private func updateTitle() {
        guard let sleepDate = sleepDate else {
            statusItem.button?.title = "💤"
            return
        }
        let remaining = max(0, Int(sleepDate.timeIntervalSinceNow.rounded()))
        let h = remaining / 3600
        let m = (remaining % 3600) / 60
        let s = remaining % 60
        if h > 0 {
            statusItem.button?.title = String(format: "💤 %d:%02d:%02d", h, m, s)
        } else {
            statusItem.button?.title = String(format: "💤 %d:%02d", m, s)
        }
    }

    @objc private func cancelTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        sleepDate = nil
        statusItem.button?.title = "💤"
        rebuildMenu()
    }

    @objc private func sleepNowAction() {
        sleepNow()
    }

    private func sleepNow() {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["sleepnow"]
        try? task.run()
        cancelTimer()
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
