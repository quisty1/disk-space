import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift MakeIcon.swift DiskSpace.iconset")
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height),
                 xRadius: radius, yRadius: radius)
}

func fill(_ shape: NSBezierPath, top: UInt32, bottom: UInt32) {
    NSGradient(starting: color(bottom), ending: color(top))?.draw(in: shape, angle: 90)
}

func artwork() {
    let tile = rounded(103, 103, 818, 818, 188)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x08152c, alpha: 0.26)
    shadow.shadowOffset = NSSize(width: 0, height: -17)
    shadow.shadowBlurRadius = 27
    shadow.set()
    color(0x1753ae).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0x0c3b9d), ending: color(0x399eff))?.draw(in: tile, angle: 72)
    let border = rounded(106, 106, 812, 812, 185)
    color(0xffffff, alpha: 0.23).setStroke()
    border.lineWidth = 4
    border.stroke()

    let drive = rounded(254, 334, 516, 360, 83)
    NSGraphicsContext.saveGraphicsState()
    let driveShadow = NSShadow()
    driveShadow.shadowColor = color(0x062762, alpha: 0.38)
    driveShadow.shadowOffset = NSSize(width: 0, height: -17)
    driveShadow.shadowBlurRadius = 28
    driveShadow.set()
    color(0x92b9ee).setFill()
    drive.fill()
    NSGraphicsContext.restoreGraphicsState()

    fill(drive, top: 0xf4faff, bottom: 0xb1d2ff)
    color(0xffffff, alpha: 0.72).setStroke()
    let rim = rounded(258, 338, 508, 352, 79)
    rim.lineWidth = 3
    rim.stroke()

    let display = rounded(315, 501, 394, 122, 40)
    fill(display, top: 0x1767c8, bottom: 0x123d8e)
    let track = rounded(354, 550, 316, 24, 12)
    color(0xc7e2ff, alpha: 0.37).setFill()
    track.fill()
    fill(rounded(354, 550, 204, 24, 12), top: 0xd0f7ff, bottom: 0x76d5ff)

    color(0x488bdc).setFill()
    rounded(617, 403, 84, 15, 7.5).fill()
    color(0x5aaafa).setFill()
    rounded(580, 403, 15, 15, 7.5).fill()
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Cannot allocate icon bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        artwork()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let png = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])?.write(to: png)
    }
}
