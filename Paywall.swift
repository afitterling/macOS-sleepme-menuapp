// Minimal AppKit paywall for the BedTime Pro one-time unlock.

import AppKit

@MainActor
final class Paywall {
    static let shared = Paywall()

    private var window: NSWindow?
    private var statusLabel: NSTextField?
    private var buyButton: NSButton?

    private init() {}

    func show() {
        if window == nil { window = makeWindow() }
        Store.shared.onChange = { [weak self] in self?.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        refresh()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "BedTime Pro"
        window.isReleasedWhenClosed = false

        let title = label("Unlock BedTime Pro", font: .boldSystemFont(ofSize: 18),
                          color: .labelColor)
        let blurb = label("A one-time purchase unlocks scheduling and every future Pro feature — forever.",
                          font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        blurb.lineBreakMode = .byWordWrapping
        blurb.maximumNumberOfLines = 0
        blurb.preferredMaxLayoutWidth = 320

        let status = label("", font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)
        statusLabel = status

        let buy = NSButton(title: "Unlock", target: self, action: #selector(buy))
        buy.bezelStyle = .rounded
        buy.keyEquivalent = "\r"
        buyButton = buy

        let restore = NSButton(title: "Restore Purchase", target: self, action: #selector(restore))
        restore.bezelStyle = .rounded

        let buttons = NSStackView(views: [restore, buy])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let stack = NSStackView(views: [title, blurb, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)

        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                stack.topAnchor.constraint(equalTo: content.topAnchor),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }
        return window
    }

    private func refresh() {
        let store = Store.shared
        if store.isPro {
            statusLabel?.stringValue = "✓ BedTime Pro is unlocked. Thank you!"
            buyButton?.title = "Unlocked"
            buyButton?.isEnabled = false
        } else {
            statusLabel?.stringValue = store.proProduct == nil
                ? "Loading…" : "One-time purchase · \(store.priceText)"
            buyButton?.title = store.proProduct == nil ? "Unlock" : "Unlock for \(store.priceText)"
            buyButton?.isEnabled = store.proProduct != nil
        }
    }

    @objc private func buy() {
        Task { await Store.shared.purchase(); refresh() }
    }

    @objc private func restore() {
        Task { await Store.shared.restore(); refresh() }
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        return field
    }
}
