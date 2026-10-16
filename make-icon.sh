#!/bin/bash
# Render the Lunis icon (a glowing crescent moon over a starlit night sky) and
# fan it out into every form the project needs:
#   • AppIcon.icns                         — the swiftc/build.sh app bundle
#   • Assets.xcassets/AppIcon.appiconset   — the Xcode / App Store build
#   • icons/                               — web favicons for the landing page
set -euo pipefail
cd "$(dirname "$0")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MASTER="$WORK/master_1024.png"

# ---- 1. Render the 1024×1024 master with AppKit ------------------------------
swift - "$MASTER" <<'SWIFT'
import AppKit

let out = CommandLine.arguments[1]
let S: CGFloat = 1024
let image = NSImage(size: NSSize(width: S, height: S))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Squircle clip.
let full = NSRect(x: 0, y: 0, width: S, height: S)
NSBezierPath(roundedRect: full, xRadius: S * 0.2237, yRadius: S * 0.2237).addClip()

// Deep night gradient, indigo → near-black, on a gentle diagonal.
NSGradient(colors: [
    NSColor(srgbRed: 0.21, green: 0.17, blue: 0.45, alpha: 1),
    NSColor(srgbRed: 0.10, green: 0.08, blue: 0.24, alpha: 1),
    NSColor(srgbRed: 0.04, green: 0.04, blue: 0.10, alpha: 1),
])!.draw(in: full, angle: -70)

// Warm glow behind the moon.
let glowCenter = CGPoint(x: S * 0.46, y: S * 0.52)
if let glow = NSGradient(colors: [
    NSColor(srgbRed: 1.0, green: 0.93, blue: 0.74, alpha: 0.55),
    NSColor(srgbRed: 1.0, green: 0.90, blue: 0.70, alpha: 0.0),
]) {
    glow.draw(fromCenter: glowCenter, radius: 0,
              toCenter: glowCenter, radius: S * 0.42, options: [])
}

// Starfield — deterministic, with a few 4-point sparkles.
func star(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ a: CGFloat) {
    NSColor(srgbRed: 1, green: 0.97, blue: 0.9, alpha: a).set()
    NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r*2, height: r*2)).fill()
}
func sparkle(_ x: CGFloat, _ y: CGFloat, _ len: CGFloat, _ a: CGFloat) {
    NSColor(srgbRed: 1, green: 0.98, blue: 0.92, alpha: a).set()
    let p = NSBezierPath()
    for (dx, dy) in [(len, 0.0), (0.0, len)] {
        p.move(to: NSPoint(x: x - CGFloat(dx), y: y - CGFloat(dy)))
        p.line(to: NSPoint(x: x + CGFloat(dx), y: y + CGFloat(dy)))
    }
    p.lineWidth = max(2, len * 0.16); p.lineCapStyle = .round; p.stroke()
}
for i in 0..<70 {
    let fx = abs(sin(Double(i) * 12.9898)).truncatingRemainder(dividingBy: 1)
    let fy = abs(sin(Double(i) * 78.233)).truncatingRemainder(dividingBy: 1)
    let fr = abs(sin(Double(i) * 3.3))
    star(CGFloat(fx) * S, CGFloat(fy) * S, CGFloat(1.2 + fr * 3.4), CGFloat(0.25 + fr * 0.6))
}
sparkle(S * 0.74, S * 0.74, S * 0.045, 0.95)
sparkle(S * 0.80, S * 0.58, S * 0.028, 0.8)
sparkle(S * 0.30, S * 0.80, S * 0.022, 0.7)

// Crescent moon drawn on its own layer, then composited with a soft glow.
let R = S * 0.255
let center = CGPoint(x: S * 0.46, y: S * 0.50)
let moon = NSImage(size: NSSize(width: S, height: S))
moon.lockFocus()
let mctx = NSGraphicsContext.current!.cgContext
// Full disk with a vertical cream gradient for a little dimension.
NSBezierPath(ovalIn: NSRect(x: center.x - R, y: center.y - R, width: R*2, height: R*2)).addClip()
NSGradient(colors: [
    NSColor(srgbRed: 1.0, green: 0.98, blue: 0.92, alpha: 1),
    NSColor(srgbRed: 0.96, green: 0.90, blue: 0.78, alpha: 1),
])!.draw(in: NSRect(x: center.x - R, y: center.y - R, width: R*2, height: R*2), angle: -90)
// Carve the crescent with an offset circle.
mctx.setBlendMode(.destinationOut)
let oc = CGPoint(x: center.x + R * 0.52, y: center.y + R * 0.30)
NSColor.black.set()
NSBezierPath(ovalIn: NSRect(x: oc.x - R*1.02, y: oc.y - R*1.02, width: R*2.04, height: R*2.04)).fill()
mctx.setBlendMode(.normal)
moon.unlockFocus()

// Composite the moon with a soft outer glow.
NSGraphicsContext.saveGraphicsState()
let sh = NSShadow()
sh.shadowColor = NSColor(srgbRed: 1, green: 0.92, blue: 0.72, alpha: 0.55)
sh.shadowBlurRadius = S * 0.05
sh.shadowOffset = .zero
sh.set()
moon.draw(in: full)
NSGraphicsContext.restoreGraphicsState()

image.unlockFocus()
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("render failed\n", stderr); exit(1)
}
try! png.write(to: URL(fileURLWithPath: out))
SWIFT

# ---- 2. AppIcon.icns ---------------------------------------------------------
ICONSET="$WORK/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s"             "$MASTER" --out "$ICONSET/icon_${s}x${s}.png"    >/dev/null
    sips -z "$((s*2))" "$((s*2))" "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o AppIcon.icns

# ---- 3. Asset catalog (Xcode / App Store) ------------------------------------
SET="Assets.xcassets/AppIcon.appiconset"
rm -rf Assets.xcassets; mkdir -p "$SET"
sips -z 16   16   "$MASTER" --out "$SET/icon_16.png"   >/dev/null
sips -z 32   32   "$MASTER" --out "$SET/icon_32.png"   >/dev/null
sips -z 64   64   "$MASTER" --out "$SET/icon_64.png"   >/dev/null
sips -z 128  128  "$MASTER" --out "$SET/icon_128.png"  >/dev/null
sips -z 256  256  "$MASTER" --out "$SET/icon_256.png"  >/dev/null
sips -z 512  512  "$MASTER" --out "$SET/icon_512.png"  >/dev/null
sips -z 1024 1024 "$MASTER" --out "$SET/icon_1024.png" >/dev/null
cat > "$SET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# ---- 4. Web favicons ---------------------------------------------------------
mkdir -p icons
sips -z 16  16  "$MASTER" --out icons/favicon-16x16.png   >/dev/null
sips -z 32  32  "$MASTER" --out icons/favicon-32x32.png   >/dev/null
sips -z 48  48  "$MASTER" --out icons/favicon-48x48.png   >/dev/null
sips -z 180 180 "$MASTER" --out icons/apple-touch-icon.png >/dev/null
sips -z 192 192 "$MASTER" --out icons/icon-192.png        >/dev/null
sips -z 512 512 "$MASTER" --out icons/icon-512.png        >/dev/null
magick icons/favicon-16x16.png icons/favicon-32x32.png icons/favicon-48x48.png icons/favicon.ico
cp "$MASTER" icons/icon-1024.png

echo "Wrote AppIcon.icns, Assets.xcassets/AppIcon.appiconset, and icons/ (favicons)"
