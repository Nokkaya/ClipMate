// 生成 ClipMate 特色应用图标：
// 深邃午夜蓝渐变底 + 多层毛玻璃历史层叠 + 精致金属夹具 + 彩色条目流光与星芒
// 用法：swift scripts/make-icon.swift <输出目录>
// 然后使用 iconutil -c icns <输出目录> -o Resources/AppIcon.icns
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"

func drawIconContents(size: CGFloat) {
    let ctx = NSGraphicsContext.current?.cgContext
    ctx?.saveGState()

    // 1. 背景 macOS Squircle
    let inset = size * 0.05
    let squircleRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: size * 0.224, yRadius: size * 0.224)

    // 底板深邃层次渐变：午夜靛蓝 -> 皇家蓝 -> 极光青蓝
    let bgGradient = NSGradient(
        colorsAndLocations: (NSColor(srgbRed: 0.08, green: 0.11, blue: 0.22, alpha: 1.0), 0.0),
                            (NSColor(srgbRed: 0.12, green: 0.24, blue: 0.54, alpha: 1.0), 0.55),
                            (NSColor(srgbRed: 0.06, green: 0.44, blue: 0.58, alpha: 1.0), 1.0)
    )!
    bgGradient.draw(in: squirclePath, angle: -52)

    // 顶部柔和微光（Top Ambient Highlight）
    ctx?.saveGState()
    squirclePath.addClip()
    let highlightRect = NSRect(x: inset, y: size * 0.65, width: size - inset * 2, height: size * 0.35)
    let topLight = NSGradient(
        starting: NSColor(white: 1.0, alpha: 0.22),
        ending: NSColor(white: 1.0, alpha: 0.0)
    )!
    topLight.draw(in: highlightRect, angle: 90)
    ctx?.restoreGState()

    // 外边缘 1pt 内描边
    NSColor(white: 1.0, alpha: 0.16).setStroke()
    squirclePath.lineWidth = max(1.0, size * 0.003)
    squirclePath.stroke()

    // 2. 底层层叠纸张 (Back Layer -3.5° 倾斜，暗示历史与堆栈)
    let sheetW = size * 0.54
    let sheetH = size * 0.65
    let sheetRadius = size * 0.065

    ctx?.saveGState()
    ctx?.translateBy(x: size * 0.5, y: size * 0.46)
    ctx?.rotate(by: -0.065) // ~ -3.7 度
    let backRect = NSRect(x: -sheetW * 0.5, y: -sheetH * 0.5, width: sheetW, height: sheetH)
    let backPath = NSBezierPath(roundedRect: backRect, xRadius: sheetRadius, yRadius: sheetRadius)

    // 阴影
    let backShadow = NSShadow()
    backShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    backShadow.shadowBlurRadius = size * 0.04
    backShadow.shadowOffset = NSSize(width: 0, height: -size * 0.015)
    backShadow.set()

    // 毛玻璃渐变层
    let backGradient = NSGradient(
        starting: NSColor(srgbRed: 0.75, green: 0.85, blue: 1.0, alpha: 0.55),
        ending: NSColor(srgbRed: 0.60, green: 0.72, blue: 0.95, alpha: 0.35)
    )!
    backGradient.draw(in: backPath, angle: -45)

    NSColor(white: 1.0, alpha: 0.35).setStroke()
    backPath.lineWidth = max(1.0, size * 0.004)
    backPath.stroke()
    ctx?.restoreGState()

    // 3. 次层层叠纸张 (Middle Layer +2.5° 倾斜)
    ctx?.saveGState()
    ctx?.translateBy(x: size * 0.51, y: size * 0.47)
    ctx?.rotate(by: 0.045) // ~ +2.6 度
    let midRect = NSRect(x: -sheetW * 0.5, y: -sheetH * 0.5, width: sheetW, height: sheetH)
    let midPath = NSBezierPath(roundedRect: midRect, xRadius: sheetRadius, yRadius: sheetRadius)

    let midShadow = NSShadow()
    midShadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    midShadow.shadowBlurRadius = size * 0.035
    midShadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    midShadow.set()

    let midGradient = NSGradient(
        starting: NSColor(srgbRed: 0.88, green: 0.92, blue: 1.0, alpha: 0.75),
        ending: NSColor(srgbRed: 0.78, green: 0.86, blue: 0.98, alpha: 0.50)
    )!
    midGradient.draw(in: midPath, angle: -45)

    NSColor(white: 1.0, alpha: 0.4).setStroke()
    midPath.lineWidth = max(1.0, size * 0.004)
    midPath.stroke()
    ctx?.restoreGState()

    // 4. 正面主剪贴板板身 (Front Main Sheet)
    let frontX = (size - sheetW) / 2
    let frontY = (size - sheetH) / 2 - size * 0.02
    let frontRect = NSRect(x: frontX, y: frontY, width: sheetW, height: sheetH)
    let frontPath = NSBezierPath(roundedRect: frontRect, xRadius: sheetRadius, yRadius: sheetRadius)

    ctx?.saveGState()
    let frontShadow = NSShadow()
    frontShadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
    frontShadow.shadowBlurRadius = size * 0.05
    frontShadow.shadowOffset = NSSize(width: 0, height: -size * 0.02)
    frontShadow.set()

    // 板体细腻陶瓷白渐变
    let frontGradient = NSGradient(
        starting: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.98),
        ending: NSColor(srgbRed: 0.93, green: 0.95, blue: 0.99, alpha: 0.96)
    )!
    frontGradient.draw(in: frontPath, angle: -65)
    ctx?.restoreGState()

    // 正面内高光描边
    NSColor(white: 1.0, alpha: 0.8).setStroke()
    frontPath.lineWidth = max(1.0, size * 0.005)
    frontPath.stroke()

    // 5. 丰富彩色条目流光（象征文本、代码、富文本、片段）
    let lineLeft = frontX + sheetW * 0.16
    let lineH = size * 0.046
    let lineR = lineH * 0.5

    // 第一行：青蓝渐变条目（含图标圆点）
    let line1W = sheetW * 0.68
    let line1Y = frontRect.midY + sheetH * 0.16
    let dotSize = lineH * 0.9
    let dot1Path = NSBezierPath(ovalIn: NSRect(x: lineLeft, y: line1Y + (lineH - dotSize) / 2, width: dotSize, height: dotSize))
    NSColor(srgbRed: 0.05, green: 0.65, blue: 0.98, alpha: 1.0).setFill()
    dot1Path.fill()

    let bar1Rect = NSRect(x: lineLeft + dotSize + size * 0.016, y: line1Y, width: line1W - dotSize - size * 0.016, height: lineH)
    let bar1Path = NSBezierPath(roundedRect: bar1Rect, xRadius: lineR, yRadius: lineR)
    let bar1Gradient = NSGradient(
        starting: NSColor(srgbRed: 0.05, green: 0.65, blue: 0.98, alpha: 0.95),
        ending: NSColor(srgbRed: 0.10, green: 0.82, blue: 0.70, alpha: 0.95)
    )!
    bar1Gradient.draw(in: bar1Path, angle: 0)

    // 第二行：神秘紫罗兰条目（代码/AI）
    let line2Y = line1Y - lineH * 1.85
    let dot2Path = NSBezierPath(ovalIn: NSRect(x: lineLeft, y: line2Y + (lineH - dotSize) / 2, width: dotSize, height: dotSize))
    NSColor(srgbRed: 0.58, green: 0.38, blue: 0.98, alpha: 1.0).setFill()
    dot2Path.fill()

    let bar2Rect = NSRect(x: lineLeft + dotSize + size * 0.016, y: line2Y, width: sheetW * 0.48, height: lineH)
    let bar2Path = NSBezierPath(roundedRect: bar2Rect, xRadius: lineR, yRadius: lineR)
    let bar2Gradient = NSGradient(
        starting: NSColor(srgbRed: 0.58, green: 0.38, blue: 0.98, alpha: 0.95),
        ending: NSColor(srgbRed: 0.80, green: 0.36, blue: 0.96, alpha: 0.95)
    )!
    bar2Gradient.draw(in: bar2Path, angle: 0)

    // 第三行：暖金琥珀条目（片段/固定星标）
    let line3Y = line2Y - lineH * 1.85
    let dot3Path = NSBezierPath(ovalIn: NSRect(x: lineLeft, y: line3Y + (lineH - dotSize) / 2, width: dotSize, height: dotSize))
    NSColor(srgbRed: 0.98, green: 0.60, blue: 0.18, alpha: 1.0).setFill()
    dot3Path.fill()

    let bar3Rect = NSRect(x: lineLeft + dotSize + size * 0.016, y: line3Y, width: sheetW * 0.36, height: lineH)
    let bar3Path = NSBezierPath(roundedRect: bar3Rect, xRadius: lineR, yRadius: lineR)
    let bar3Gradient = NSGradient(
        starting: NSColor(srgbRed: 0.98, green: 0.60, blue: 0.18, alpha: 0.95),
        ending: NSColor(srgbRed: 0.98, green: 0.42, blue: 0.22, alpha: 0.95)
    )!
    bar3Gradient.draw(in: bar3Path, angle: 0)

    // 右下角：星芒/灵动 AI 标志点缀 (Sparkle Badge)
    let starCenter = CGPoint(x: frontRect.maxX - sheetW * 0.22, y: frontRect.minY + sheetH * 0.24)
    let starR = size * 0.05
    let starPath = NSBezierPath()
    starPath.move(to: CGPoint(x: starCenter.x, y: starCenter.y + starR))
    starPath.curve(to: CGPoint(x: starCenter.x + starR, y: starCenter.y),
                   controlPoint1: CGPoint(x: starCenter.x, y: starCenter.y + starR * 0.3),
                   controlPoint2: CGPoint(x: starCenter.x + starR * 0.3, y: starCenter.y))
    starPath.curve(to: CGPoint(x: starCenter.x, y: starCenter.y - starR),
                   controlPoint1: CGPoint(x: starCenter.x + starR * 0.3, y: starCenter.y),
                   controlPoint2: CGPoint(x: starCenter.x, y: starCenter.y - starR * 0.3))
    starPath.curve(to: CGPoint(x: starCenter.x - starR, y: starCenter.y),
                   controlPoint1: CGPoint(x: starCenter.x, y: starCenter.y - starR * 0.3),
                   controlPoint2: CGPoint(x: starCenter.x - starR * 0.3, y: starCenter.y))
    starPath.curve(to: CGPoint(x: starCenter.x, y: starCenter.y + starR),
                   controlPoint1: CGPoint(x: starCenter.x - starR * 0.3, y: starCenter.y),
                   controlPoint2: CGPoint(x: starCenter.x, y: starCenter.y + starR * 0.3))
    starPath.close()

    let starGradient = NSGradient(
        starting: NSColor(srgbRed: 0.35, green: 0.65, blue: 1.0, alpha: 0.95),
        ending: NSColor(srgbRed: 0.72, green: 0.42, blue: 1.0, alpha: 0.95)
    )!
    starGradient.draw(in: starPath, angle: 45)

    // 6. 顶部精致钛合金金属夹具 (Polished Metal Clip)
    let clipW = sheetW * 0.46
    let clipH = sheetH * 0.14
    let clipRect = NSRect(x: (size - clipW) / 2, y: frontRect.maxY - clipH * 0.58, width: clipW, height: clipH)
    let clipPath = NSBezierPath(roundedRect: clipRect, xRadius: clipH * 0.45, yRadius: clipH * 0.45)

    ctx?.saveGState()
    let clipShadow = NSShadow()
    clipShadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    clipShadow.shadowBlurRadius = size * 0.02
    clipShadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
    clipShadow.set()

    // 金属渐变
    let metalGradient = NSGradient(
        colorsAndLocations: (NSColor(srgbRed: 0.90, green: 0.93, blue: 0.98, alpha: 1.0), 0.0),
                            (NSColor(srgbRed: 0.75, green: 0.80, blue: 0.88, alpha: 1.0), 0.5),
                            (NSColor(srgbRed: 0.85, green: 0.89, blue: 0.95, alpha: 1.0), 1.0)
    )!
    metalGradient.draw(in: clipPath, angle: 90)
    ctx?.restoreGState()

    // 夹子顶部高光细线
    NSColor(white: 1.0, alpha: 0.9).setStroke()
    clipPath.lineWidth = max(1.0, size * 0.004)
    clipPath.stroke()

    // 夹具中心槽孔
    let slotW = clipW * 0.42
    let slotH = clipH * 0.32
    let slotRect = NSRect(x: (size - slotW) / 2, y: clipRect.midY - slotH / 2, width: slotW, height: slotH)
    let slotPath = NSBezierPath(roundedRect: slotRect, xRadius: slotH * 0.5, yRadius: slotH * 0.5)
    NSColor(srgbRed: 0.52, green: 0.58, blue: 0.68, alpha: 1.0).setFill()
    slotPath.fill()

    ctx?.restoreGState()
}

/// 固定像素渲染
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
print("完成：\(outputDir)/")
