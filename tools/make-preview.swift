// 生成 README 顶部的预览图
//
// 关键点：竖条用 NSBezierPath 直接在目标尺寸上绘制，不做位图缩放 —— 这样边缘是锐利的。
// 画布按 2x 输出（1760px 宽），GitHub README 正文栏约 880px，正好 retina 清晰。

import AppKit

// MARK: - 颜色

let bgColor     = NSColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 1)
let stripDark   = NSColor(srgbRed: 0.15, green: 0.16, blue: 0.19, alpha: 1)
let titleColor  = NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)
let labelColor  = NSColor(srgbRed: 0.62, green: 0.65, blue: 0.72, alpha: 1)
let dimColor    = NSColor(srgbRed: 0.42, green: 0.45, blue: 0.52, alpha: 1)

// MARK: - 画一根竖条（矢量，任意尺寸都锐利）
//
// 画布是非翻转坐标系（原点在左下），所以"底部"是 minY。
// 轮廓恒定是一根胶囊；底槽淡色；填充满宽从底部升起。

func drawBar(in r: NSRect, fraction: Double?, trackAlpha: CGFloat = 0.20) {
    let capsule = NSBezierPath(roundedRect: r, xRadius: r.width / 2, yRadius: r.width / 2)
    NSColor.white.withAlphaComponent(fraction == nil ? 0.13 : trackAlpha).setFill()
    capsule.fill()

    guard let f = fraction else { return }
    let fh = r.height * max(0, min(1, f))
    guard fh >= 0.5 else { return }

    NSGraphicsContext.saveGraphicsState()
    capsule.addClip()
    NSColor.white.setFill()
    NSRect(x: r.minX, y: r.minY, width: r.width, height: fh).fill()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - SF Symbol 上色

func tintedSymbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let sym = base.withSymbolConfiguration(
              NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
    else { return nil }
    return NSImage(size: sym.size, flipped: false) { rect in
        sym.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

// MARK: - 画布

let W: CGFloat = 1760
let H: CGFloat = 500
let pad: CGFloat = 72

// 非翻转画布，提供把"从上往下数"的 y 换算成绘图坐标的辅助
func topY(_ top: CGFloat, _ h: CGFloat) -> CGFloat { H - top - h }

let image = NSImage(size: NSSize(width: W, height: H), flipped: false) { _ in
    bgColor.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    // ---- 标题 ----
    let title = NSAttributedString(string: "ClaudeMeter", attributes: [
        .font: NSFont.systemFont(ofSize: 40, weight: .semibold),
        .foregroundColor: titleColor,
    ])
    title.draw(at: NSPoint(x: pad, y: topY(40, 48)))

    let sub = NSAttributedString(string: "菜单栏里的一根竖条 = 5 小时会话剩余用量",
                                attributes: [
        .font: NSFont.systemFont(ofSize: 24, weight: .regular),
        .foregroundColor: labelColor,
    ])
    sub.draw(at: NSPoint(x: pad + title.size().width + 20, y: topY(46, 30)))

    // ---- 模拟菜单栏条 ----
    let stripTop: CGFloat = 120
    let stripH: CGFloat = 76
    let stripRect = NSRect(x: pad, y: topY(stripTop, stripH), width: W - pad * 2, height: stripH)
    stripDark.setFill()
    NSBezierPath(roundedRect: stripRect, xRadius: 14, yRadius: 14).fill()

    // 条里的元素：右对齐排布
    let barW: CGFloat = 30, barH: CGFloat = 54
    let itemY = stripRect.minY + (stripH - barH) / 2
    var cursor = stripRect.maxX - 44

    let clock = NSAttributedString(string: "17:39", attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85),
    ])
    clock.draw(at: NSPoint(x: cursor - clock.size().width, y: stripRect.minY + (stripH - clock.size().height) / 2))
    cursor -= clock.size().width + 34

    for name in ["battery.100", "wifi"] {
        if let sym = tintedSymbol(name, pointSize: 24, color: NSColor.white.withAlphaComponent(0.85)) {
            let w = sym.size.width, h = sym.size.height
            sym.draw(in: NSRect(x: cursor - w, y: stripRect.minY + (stripH - h) / 2, width: w, height: h))
            cursor -= w + 30
        }
    }

    // ClaudeMeter 的竖条
    drawBar(in: NSRect(x: cursor - barW, y: itemY, width: barW, height: barH), fraction: 0.99)
    cursor -= barW + 26

    let hint = NSAttributedString(string: "← 菜单栏里的样子", attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .regular),
        .foregroundColor: dimColor,
    ])
    hint.draw(at: NSPoint(x: cursor - hint.size().width, y: stripRect.minY + (stripH - hint.size().height) / 2))

    // ---- 分节标题 ----
    let section = NSAttributedString(string: "不同剩余量下的表现", attributes: [
        .font: NSFont.systemFont(ofSize: 24, weight: .medium),
        .foregroundColor: labelColor,
    ])
    section.draw(at: NSPoint(x: pad, y: topY(240, 32)))

    // ---- 状态行 ----
    let states: [(Double?, String)] = [
        (0.99, "99%"), (0.75, "75%"), (0.50, "50%"), (0.23, "23%"), (nil, "无数据"),
    ]
    let rowTop: CGFloat = 292
    let rowBarH: CGFloat = 86, rowBarW: CGFloat = 86 * 10 / 18
    let cellW = (W - pad * 2) / CGFloat(states.count)

    for (i, s) in states.enumerated() {
        let cx = pad + cellW * (CGFloat(i) + 0.5)
        drawBar(in: NSRect(x: cx - rowBarW / 2, y: topY(rowTop, rowBarH),
                           width: rowBarW, height: rowBarH),
                fraction: s.0)
        let lab = NSAttributedString(string: s.1, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .regular),
            .foregroundColor: s.0 == nil ? dimColor : labelColor,
        ])
        lab.draw(at: NSPoint(x: cx - lab.size().width / 2, y: topY(rowTop + rowBarH + 18, 30)))
    }

    // ---- 页脚 ----
    let foot = NSAttributedString(string: "填充从底部升起，轮廓恒定为胶囊 · 点击查看 5 小时 / 每周详情",
                                 attributes: [
        .font: NSFont.systemFont(ofSize: 21, weight: .regular),
        .foregroundColor: dimColor,
    ])
    foot.draw(at: NSPoint(x: pad, y: topY(H - 54, 28)))

    return true
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/preview.png"
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)  \(rep.pixelsWide)x\(rep.pixelsHigh)")
