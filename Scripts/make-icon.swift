import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let bounds = NSRect(x: 0, y: 0, width: size, height: size)
NSColor(calibratedRed: 0.93, green: 0.91, blue: 0.86, alpha: 1).setFill()
NSBezierPath(rect: bounds).fill()

func tile(_ rect: NSRect, _ color: NSColor, _ radius: CGFloat) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

let pad: CGFloat = 96
let gap: CGFloat = 28
let canvas = bounds.insetBy(dx: pad, dy: pad)
tile(
    NSRect(x: canvas.minX, y: canvas.minY, width: canvas.width * 0.56, height: canvas.height),
    NSColor(calibratedRed: 0.36, green: 0.55, blue: 0.44, alpha: 1),
    48
)
let rightX = canvas.minX + canvas.width * 0.56 + gap
let rightW = canvas.maxX - rightX
tile(
    NSRect(x: rightX, y: canvas.minY + canvas.height * 0.46, width: rightW, height: canvas.height * 0.54),
    NSColor(calibratedRed: 0.78, green: 0.50, blue: 0.28, alpha: 1),
    42
)
let bottomH = canvas.height * 0.46 - gap
let half = (rightW - gap) / 2
tile(
    NSRect(x: rightX, y: canvas.minY, width: half, height: bottomH),
    NSColor(calibratedRed: 0.76, green: 0.38, blue: 0.32, alpha: 1),
    36
)
tile(
    NSRect(x: rightX + half + gap, y: canvas.minY, width: half, height: bottomH),
    NSColor(calibratedRed: 0.28, green: 0.45, blue: 0.58, alpha: 1),
    36
)
image.unlockFocus()

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("icon failed\n", stderr)
    exit(1)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: url)
