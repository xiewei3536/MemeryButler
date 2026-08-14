// 產生 1024×1024 app 圖示 PNG（headless 安全:繪進固定尺寸 bitmap）
// 用法: swift make_icon.swift <輸出路徑.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let px = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("無法建立 bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let size = CGFloat(px)
// macOS 圖示標準留白（約 10%）
let rect = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.09, dy: size * 0.09)
let radius = rect.width * 0.225
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// 藍→靛紫漸層
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.25, green: 0.52, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.38, green: 0.26, blue: 0.92, alpha: 1),
])!
gradient.draw(in: path, angle: -62)

// 頂部柔光
path.addClip()
let glow = NSGradient(colors: [
    NSColor(calibratedWhite: 1.0, alpha: 0.22),
    NSColor(calibratedWhite: 1.0, alpha: 0.0),
])!
glow.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)

// 中央 memorychip 符號（白色）
if let symbol = NSImage(systemSymbolName: "memorychip.fill", accessibilityDescription: nil),
   let configured = symbol.withSymbolConfiguration(.init(pointSize: 460, weight: .medium)) {
    let s = configured.size
    let tinted = NSImage(size: s)
    tinted.lockFocus()
    configured.draw(in: NSRect(origin: .zero, size: s))
    NSColor.white.set()
    NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
    tinted.unlockFocus()

    let maxW = rect.width * 0.62
    let scale = min(maxW / s.width, maxW / s.height)
    let drawSize = NSSize(width: s.width * scale, height: s.height * scale)
    let origin = NSPoint(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2)

    // 微陰影增加立體感
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()

    tinted.draw(in: NSRect(origin: origin, size: drawSize))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG 轉換失敗") }
try! png.write(to: URL(fileURLWithPath: out))
print("已輸出 \(out)")
