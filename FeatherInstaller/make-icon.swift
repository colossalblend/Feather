import AppKit
import Foundation
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.20, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let symbol = NSImage(systemSymbolName: "shippingbox.and.arrow.backward.fill", accessibilityDescription: nil)!
let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .bold).applying(.init(paletteColors: [.systemOrange]))
symbol.withSymbolConfiguration(config)!.draw(in: NSRect(x: 230, y: 320, width: 564, height: 500))
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 104, weight: .heavy), .foregroundColor: NSColor.white]
let text = NSAttributedString(string: "INSTALLER", attributes: attributes)
text.draw(at: NSPoint(x: (1024 - text.size().width) / 2, y: 155))
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
