import Cocoa

let logoPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "magpulselogo.png"
let outPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "resources/AppIcon.icns"

guard let src = NSImage(contentsOfFile: logoPath) else {
    print("Error: Could not load image from \(logoPath)")
    exit(1)
}

struct IconEntry {
    let tag: String
    let pixelSize: Int
}

// Complete set of modern macOS ICNS tags (PNG-based) including Retina 1024x1024 (ic10)
let entries: [IconEntry] = [
    IconEntry(tag: "icp4", pixelSize: 16),
    IconEntry(tag: "ic11", pixelSize: 32),
    IconEntry(tag: "icp5", pixelSize: 32),
    IconEntry(tag: "ic12", pixelSize: 64),
    IconEntry(tag: "ic07", pixelSize: 128),
    IconEntry(tag: "ic13", pixelSize: 256),
    IconEntry(tag: "ic08", pixelSize: 256),
    IconEntry(tag: "ic14", pixelSize: 512),
    IconEntry(tag: "ic09", pixelSize: 512),
    IconEntry(tag: "ic10", pixelSize: 1024)
]

var payload = Data()

for entry in entries {
    let s = entry.pixelSize
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: s,
        pixelsHigh: s,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.interpolationQuality = .high
    
    // Draw full-bleed square edge-to-edge (no shrinking, no grey gap)
    src.draw(in: CGRect(x: 0, y: 0, width: s, height: s), from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    
    guard let pngData = rep.representation(using: .png, properties: [:]) else { continue }
    
    // 4-byte ASCII OSType tag
    payload.append(entry.tag.data(using: .ascii)!)
    
    // 4-byte Big-Endian total block length (8 header + png bytes)
    var blockLen = UInt32(8 + pngData.count).bigEndian
    payload.append(Data(bytes: &blockLen, count: 4))
    
    // Raw PNG data
    payload.append(pngData)
}

var fullFile = Data()
fullFile.append("icns".data(using: .ascii)!)
var totalLen = UInt32(8 + payload.count).bigEndian
fullFile.append(Data(bytes: &totalLen, count: 4))
fullFile.append(payload)

try! fullFile.write(to: URL(fileURLWithPath: outPath))
print("Successfully generated complete modern macOS ICNS with 1024x1024 retina support at: \(outPath) (\(fullFile.count) bytes)")
