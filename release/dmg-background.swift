// Draws the DMG window background (660x400 @1x/@2x TIFF is overkill; one 1320x800 PNG shown at 660x400).
// Usage: swift release/dmg-background.swift OUT.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"
let w = 1320, h = 800
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGradient(starting: NSColor(red: 0.96, green: 0.98, blue: 0.96, alpha: 1), ending: NSColor(red: 0.89, green: 0.94, blue: 0.91, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
let ink = NSColor(white: 0.25, alpha: 0.8)
let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 34, weight: .medium), .foregroundColor: ink, .paragraphStyle: para]
"Drag Kanso to Applications".draw(in: NSRect(x: 0, y: 130, width: w, height: 50), withAttributes: attrs)
// arrow between the two icon slots (icons sit at x=180 and x=480 in 1x points)
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 540, y: 470)); arrow.line(to: NSPoint(x: 760, y: 470))
arrow.move(to: NSPoint(x: 725, y: 505)); arrow.line(to: NSPoint(x: 765, y: 470)); arrow.line(to: NSPoint(x: 725, y: 435))
arrow.lineWidth = 7; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
ink.withAlphaComponent(0.45).setStroke(); arrow.stroke()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
