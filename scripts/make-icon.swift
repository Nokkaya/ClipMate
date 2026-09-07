// 生成 ClipMate 应用图标：渐变底 + 剪贴板 + 历史列表线条。
// 用法：swift scripts/make-icon.swift <输出目录>
// 然后用 iconutil -c icns <目录> -o Resources/AppIcon.icns 打包。
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"

func drawIconContents(size: CGFloat) {
    // 背景圆角矩形 + 对角渐变（蓝 → 青绿，与 App 内类型色一致）
    let inset = size * 0.05
    let bgRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.215, yRadius: size * 0.215)
    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.24, green: 0.48, blue: 0.94, alpha: 1),
        ending: NSColor(srgbRed: 0.05, green: 0.63, blue: 0.56, alpha: 1)
    )!
    gradient.draw(in: bgPath, angle: -55)

    // 剪贴板主体
    let clipW = size * 0.54
    let clipH = size * 0.64
    let clipRect = NSRect(x: (size - clipW) / 2, y: (size - clipH) / 2 - size * 0.02,
                          width: clipW, height: clipH)
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.97).setFill()
    NSBezierPath(roundedRect: clipRect, xRadius: size * 0.055, yRadius: size * 0.055).fill()

    // 顶部夹片
    let tabW = clipW * 0.42
    let tabH = clipH * 0.13
    let tabRect = NSRect(x: (size - tabW) / 2, y: clipRect.maxY - tabH * 0.55,
                         width: tabW, height: tabH)
    NSColor(srgbRed: 0.82, green: 0.86, blue: 0.93, alpha: 1).setFill()
    NSBezierPath(roundedRect: tabRect, xRadius: tabH * 0.4, yRadius: tabH * 0.4).fill()

    // 历史列表线条（首行高亮，后面半透明，暗示"多级历史"）
    let lineH = size * 0.042
    let lineX = clipRect.midX - clipW * 0.31
    let widths: [CGFloat] = [0.62, 0.44, 0.53]
    for (index, widthRatio) in widths.enumerated() {
        let y = clipRect.midY + clipH * 0.10 - CGFloat(index) * lineH * 2.15 - lineH
        let lineRect = NSRect(x: lineX, y: y, width: clipW * widthRatio, height: lineH)
        NSColor(srgbRed: 0.24, green: 0.48, blue: 0.94,
                alpha: index == 0 ? 1 : (index == 1 ? 0.5 : 0.3)).setFill()
        NSBezierPath(roundedRect: lineRect, xRadius: lineH / 2, yRadius: lineH / 2).fill()
    }
}

/// 固定像素渲染：位图上下文中 1pt == 1px，规避 Retina 屏 2x 缩放导致尺寸翻倍。
func renderIconPNG(pixel: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixel, pixelsHigh: pixel,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixel, height: pixel)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIconContents(size: CGFloat(pixel))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
}

func writePNG(_ data: Data?, to path: String) {
    guard let data else { fatalError("PNG 渲染失败: \(path)") }
    try! data.write(to: URL(fileURLWithPath: path))
}

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// iconset 规范：每档 1x 与 2x
let specs: [(name: String, pixel: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for spec in specs {
    writePNG(renderIconPNG(pixel: spec.pixel), to: outputDir + "/" + spec.name)
    print("生成 \(spec.name)")
}
print("完成：\(outputDir)/（下一步 iconutil -c icns）")
