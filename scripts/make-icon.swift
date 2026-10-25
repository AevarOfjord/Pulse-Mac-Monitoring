import AppKit

let destination = CommandLine.arguments[1]
var icns = Data("icns".utf8)
func bigEndian(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var chunks = Data()
for (size, type) in [(128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size)
    NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.14, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.05, y: s * 0.05, width: s * 0.9, height: s * 0.9), xRadius: s * 0.2, yRadius: s * 0.2).fill()
    let path = NSBezierPath()
    for (index, point) in [(0.20, 0.49), (0.34, 0.49), (0.41, 0.68), (0.51, 0.29), (0.60, 0.57), (0.66, 0.49), (0.80, 0.49)].enumerated() {
        let p = NSPoint(x: s * point.0, y: s * point.1)
        if index == 0 { path.move(to: p) } else { path.line(to: p) }
    }
    NSColor(calibratedRed: 0.45, green: 0.89, blue: 0.74, alpha: 1).setStroke()
    path.lineWidth = s * 0.047; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let png = bitmap.representation(using: .png, properties: [:])!
    chunks.append(Data(type.utf8)); chunks.append(bigEndian(UInt32(png.count + 8))); chunks.append(png)
}
icns.append(bigEndian(UInt32(chunks.count + 8))); icns.append(chunks)
try icns.write(to: URL(fileURLWithPath: destination))
