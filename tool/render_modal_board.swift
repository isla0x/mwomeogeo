// Compose exact Flutter renders into a review board. Run from the project root.
import AppKit
let width = 1320, height = 1060
let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1)
}
color(239, 237, 232).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
          _ weight: NSFont.Weight = .regular, _ foreground: NSColor = color(39,36,32)) {
    (value as NSString).draw(at: NSPoint(x: x,y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: foreground])
}
text("뭐먹어?", 45, 992, 30, .bold)
text("알림과 선택 화면 리디자인", 203, 996, 20, .medium, color(104,117,128))
let entries = [("기록 메뉴", "09-record-menu"), ("삭제 확인", "10-delete-dialog"), ("사진 선택", "11-photo-options")]
for (i, entry) in entries.enumerated() {
    let x = CGFloat(45 + i * 420)
    text(entry.0, x, 940, 19, .semibold)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: NSRect(x:x, y:70, width:390, height:844), xRadius:26, yRadius:26).addClip()
    let image = NSImage(contentsOfFile: "build/previews/\(entry.1).png")!
    image.draw(in: NSRect(x:x,y:70,width:390,height:844))
    NSGraphicsContext.restoreGraphicsState()
}
text("CHERRY MILK  /  실제 앱 화면 렌더링 · Build 11", 45, 25, 13, .medium, color(104,117,128))
NSGraphicsContext.restoreGraphicsState()
let output = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try output.write(to: URL(fileURLWithPath: "preview/13-modal-redesign.png"))
