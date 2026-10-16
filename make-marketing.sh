#!/bin/bash
# Generate marketing imagery for Lunis: an App Store screenshot and a
# landing-page hero, both built around a faithful render of the app menu.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p marketing
[ -f AppIcon.icns ] || ./make-icon.sh

swift - "$(pwd)" <<'SWIFT'
import AppKit

let root = CommandLine.arguments[1]

// ---- palette ------------------------------------------------------------
let cream   = NSColor(srgbRed: 0.98, green: 0.95, blue: 0.86, alpha: 1)
let dim      = NSColor(srgbRed: 0.70, green: 0.71, blue: 0.82, alpha: 1)
let accent  = NSColor(srgbRed: 0.30, green: 0.42, blue: 0.95, alpha: 1)
let panelBG = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.18, alpha: 0.98)

func font(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: s, weight: w)
}

// ---- helpers ------------------------------------------------------------
func roundedPath(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

func nightBackground(_ size: NSSize) {
    let rect = NSRect(origin: .zero, size: size)
    NSGradient(colors: [
        NSColor(srgbRed: 0.16, green: 0.13, blue: 0.34, alpha: 1),
        NSColor(srgbRed: 0.06, green: 0.05, blue: 0.13, alpha: 1),
    ])!.draw(in: rect, angle: -90)
    // Deterministic starfield.
    cream.withAlphaComponent(0.85).set()
    for i in 0..<90 {
        let fx = abs(sin(Double(i) * 12.9898)) .truncatingRemainder(dividingBy: 1)
        let fy = abs(sin(Double(i) * 78.233)) .truncatingRemainder(dividingBy: 1)
        let r = CGFloat(0.6 + (abs(sin(Double(i) * 3.7)) * 2.2))
        let x = CGFloat(fx) * size.width
        let y = CGFloat(fy) * size.height
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: r, height: r)).fill()
    }
}

func drawSymbol(_ name: String, size: CGFloat, color: NSColor, centerX: CGFloat, centerY: CGFloat) {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else { return }
    let s = base.size
    let tinted = NSImage(size: s)
    tinted.lockFocus()
    base.draw(in: NSRect(origin: .zero, size: s))
    color.set()
    NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(in: NSRect(x: centerX - s.width / 2, y: centerY - s.height / 2,
                           width: s.width, height: s.height))
}

func text(_ string: String, _ f: NSFont, _ color: NSColor, x: CGFloat, y: CGFloat) {
    (string as NSString).draw(at: NSPoint(x: x, y: y),
        withAttributes: [.font: f, .foregroundColor: color])
}

// A row in the mock menu: (symbol, label, checked, highlighted, isSeparator).
struct Row { let sym: String; let label: String; let pro: Bool; let checked: Bool; let hi: Bool; let sep: Bool
    init(_ s: String = "", _ l: String = "", pro: Bool = false, checked: Bool = false, hi: Bool = false, sep: Bool = false) {
        sym = s; label = l; self.pro = pro; self.checked = checked; self.hi = hi; self.sep = sep } }

let rows: [Row] = [
    Row("powersleep", "Sleep Now", hi: true),
    Row(sep: true),
    Row("clock", "15 minutes"),
    Row("clock", "30 minutes"),
    Row("clock", "1 hour"),
    Row("slider.horizontal.3", "Custom…"),
    Row("lock", "Schedule a Time…", pro: true),
    Row(sep: true),
    Row("moon.zzz", "Bedtime Lightning"),
    Row(sep: true),
    Row("moon", "Wind Down the Lights", checked: true),
    Row("crown", "Unlock Lunis Pro…"),
    Row(sep: true),
    Row("gearshape", "Settings…"),
    Row("power", "Quit"),
]

// Draws the menu panel with its origin at (ox, oy), returns its size.
@discardableResult
func drawMenu(ox: CGFloat, oy: CGFloat, scale: CGFloat) -> NSSize {
    let pad: CGFloat = 18 * scale
    let rowH: CGFloat = 46 * scale
    let sepH: CGFloat = 17 * scale
    let width: CGFloat = 420 * scale
    var height = pad * 2
    for r in rows { height += r.sep ? sepH : rowH }

    let panel = NSRect(x: ox, y: oy, width: width, height: height)
    // Soft shadow.
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.55)
    sh.shadowBlurRadius = 40 * scale; sh.shadowOffset = NSSize(width: 0, height: -12 * scale); sh.set()
    panelBG.set()
    roundedPath(panel, 22 * scale).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()   // balanced by the restore at the end
    roundedPath(panel, 22 * scale).addClip()

    // Rows are drawn top-down; AppKit y is bottom-up, so start from the top.
    var y = oy + height - pad
    let iconX = ox + pad + 16 * scale
    let textX = ox + pad + 40 * scale
    for r in rows {
        if r.sep {
            y -= sepH
            cream.withAlphaComponent(0.10).set()
            NSRect(x: ox + pad, y: y + sepH/2, width: width - pad*2, height: 1).fill()
            continue
        }
        y -= rowH
        let mid = y + rowH/2
        if r.hi {
            accent.set()
            roundedPath(NSRect(x: ox + 8*scale, y: y + 3*scale,
                               width: width - 16*scale, height: rowH - 6*scale), 8*scale).fill()
        }
        if r.checked {
            drawSymbol("checkmark", size: 13*scale, color: r.hi ? .white : cream,
                       centerX: ox + pad + 2*scale, centerY: mid)
        }
        drawSymbol(r.sym, size: 17*scale, color: r.hi ? .white : dim, centerX: iconX, centerY: mid)
        let labelColor = r.hi ? NSColor.white : cream
        text(r.label, font(19*scale), labelColor, x: textX, y: mid - 12*scale)
        if r.pro {
            let tag = "PRO"
            let tagFont = font(11*scale, .bold)
            let tw = (tag as NSString).size(withAttributes: [.font: tagFont]).width
            let tagRect = NSRect(x: ox + width - pad - tw - 18*scale, y: mid - 11*scale,
                                 width: tw + 16*scale, height: 22*scale)
            accent.withAlphaComponent(r.hi ? 0.0 : 0.9).set()
            (r.hi ? NSColor.white.withAlphaComponent(0.25) : accent.withAlphaComponent(0.9)).set()
            roundedPath(tagRect, 6*scale).fill()
            text(tag, tagFont, .white, x: tagRect.minX + 8*scale, y: mid - 7*scale)
        }
    }
    NSGraphicsContext.restoreGraphicsState() // undo addClip
    return panel.size
}

func appIcon(_ side: CGFloat, x: CGFloat, y: CGFloat) {
    if let icon = NSImage(contentsOfFile: root + "/AppIcon.icns") {
        icon.draw(in: NSRect(x: x, y: y, width: side, height: side))
    }
}

func compose(_ size: NSSize, landing: Bool, to path: String) {
    let img = NSImage(size: size)
    img.lockFocus()
    NSGraphicsContext.current?.saveGraphicsState()
    nightBackground(size)

    // Menu panel on the right.
    let scale: CGFloat = size.height / 900
    let menuW = 420 * scale
    let menuX = size.width - menuW - 120 * scale
    var menuH: CGFloat = 36 * scale
    for r in rows { menuH += r.sep ? 17*scale : 46*scale }
    let menuY = (size.height - menuH) / 2
    drawMenu(ox: menuX, oy: menuY, scale: scale)

    // Left column: icon, wordmark, tagline, bullets.
    let leftX = 120 * scale
    appIcon(150 * scale, x: leftX, y: size.height - 150*scale - 110*scale)

    text("Lunis", font(120*scale, .heavy), cream, x: leftX - 4*scale, y: size.height - 150*scale - 290*scale)
    text("Wind your Mac down to sleep — gently.",
         font(40*scale, .medium), dim, x: leftX, y: size.height - 150*scale - 360*scale)

    let bullets = [
        ("powersleep", "One-tap Sleep Now, or a countdown timer"),
        ("moon.zzz", "Dims the screen as bedtime approaches"),
        ("calendar", "Schedule a nightly sleep time"),
        ("menubar.rectangle", "Lives quietly in your menu bar"),
    ]
    var by = size.height - 150*scale - 470*scale
    for (sym, line) in bullets {
        drawSymbol(sym, size: 22*scale, color: accent, centerX: leftX + 16*scale, centerY: by + 12*scale)
        text(line, font(30*scale, .regular), cream, x: leftX + 46*scale, y: by)
        by -= 64*scale
    }

    if landing {
        let cta = NSRect(x: leftX, y: by - 30*scale, width: 360*scale, height: 76*scale)
        accent.set(); roundedPath(cta, 16*scale).fill()
        text("Download for macOS", font(28*scale, .semibold), .white,
             x: cta.minX + 44*scale, y: cta.midY - 18*scale)
    }

    NSGraphicsContext.current?.restoreGraphicsState()
    img.unlockFocus()

    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try! png.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path)")
}

compose(NSSize(width: 2880, height: 1800), landing: false, to: root + "/marketing/lunis-appstore.png")
compose(NSSize(width: 2400, height: 1260), landing: true,  to: root + "/marketing/lunis-hero.png")
SWIFT

echo "Marketing images in marketing/"
