import AppKit

guard CommandLine.arguments.count == 2 else { exit(2) }
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let background = NSBezierPath(roundedRect: NSRect(x: 18, y: 18, width: 988, height: 988),
                              xRadius: 210, yRadius: 210)
NSColor(calibratedRed: 0.11, green: 0.15, blue: 0.21, alpha: 1).setFill()
background.fill()

let shell = NSBezierPath(roundedRect: NSRect(x: 166, y: 330, width: 660, height: 364),
                         xRadius: 91, yRadius: 91)
shell.lineWidth = 30
NSColor(calibratedWhite: 0.95, alpha: 1).setStroke()
shell.stroke()

let cap = NSBezierPath(roundedRect: NSRect(x: 838, y: 441, width: 43, height: 143),
                       xRadius: 19, yRadius: 19)
NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
cap.fill()

let charge = NSBezierPath(roundedRect: NSRect(x: 197, y: 361, width: 402, height: 302),
                          xRadius: 62, yRadius: 62)
NSColor(calibratedRed: 0.33, green: 0.65, blue: 0.94, alpha: 1).setFill()
charge.fill()

let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 520, y: 652))
bolt.line(to: NSPoint(x: 405, y: 493))
bolt.line(to: NSPoint(x: 490, y: 493))
bolt.line(to: NSPoint(x: 449, y: 372))
bolt.line(to: NSPoint(x: 615, y: 542))
bolt.line(to: NSPoint(x: 525, y: 542))
bolt.close()
NSColor(calibratedWhite: 1, alpha: 1).setFill()
bolt.fill()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
