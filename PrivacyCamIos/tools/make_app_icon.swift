// 앱 아이콘(1024, 알파 없음) 생성: 뷰파인더 안 인물 흉상, 오른쪽 절반 모자이크, 가운데 비교 핸들.
// swift tools/make_app_icon.swift PrivacyCam/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let s = CGFloat(size)
func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// 위가 y=0 인 좌표로 그린다.
ctx.translateBy(x: 0, y: s)
ctx.scaleBy(x: 1, y: -1)

// 배경: 밤 남색 대각 그라데이션 (Theme.background 다크).
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x3A4585), rgb(0x141A2E)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: s, y: s), options: [])

// 사진 카드 내용(배경 + 흉상)을 따로 그린 뒤, 오른쪽 절반을 블록 평균색으로 모자이크한다.
let card = CGRect(x: 232, y: 232, width: 560, height: 560)
let cw = Int(card.width)
let content = CGContext(data: nil, width: cw, height: cw, bitsPerComponent: 8, bytesPerRow: cw * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
content.translateBy(x: 0, y: card.height)
content.scaleBy(x: 1, y: -1)
content.setFillColor(rgb(0xECEEFA))
content.fill(CGRect(x: 0, y: 0, width: card.width, height: card.height))
content.setFillColor(rgb(0x5B67D8))
content.fillEllipse(in: CGRect(x: 280 - 105, y: 98, width: 210, height: 210))
content.addPath(CGPath(roundedRect: CGRect(x: 280 - 210, y: 348, width: 420, height: 320), cornerWidth: 190, cornerHeight: 190, transform: nil))
content.fillPath()

let block = 56
let px = content.data!.assumingMemoryBound(to: UInt8.self)
for by in stride(from: 0, to: cw, by: block) {
    for bx in stride(from: cw / 2, to: cw, by: block) {
        let ys = by..<min(by + block, cw), xs = bx..<min(bx + block, cw)
        var sum = [0, 0, 0]
        for y in ys { for x in xs { for c in 0..<3 { sum[c] += Int(px[(y * cw + x) * 4 + c]) } } }
        let n = ys.count * xs.count
        for y in ys { for x in xs { for c in 0..<3 { px[(y * cw + x) * 4 + c] = UInt8(sum[c] / n) } } }
    }
}

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(CGPath(roundedRect: card, cornerWidth: 112, cornerHeight: 112, transform: nil))
ctx.setFillColor(rgb(0xECEEFA))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: card, cornerWidth: 112, cornerHeight: 112, transform: nil))
ctx.clip()
// 뒤집힌 좌표계에서 CGImage 를 똑바로 그리려면 다시 뒤집는다.
ctx.translateBy(x: card.minX, y: card.maxY)
ctx.scaleBy(x: 1, y: -1)
ctx.draw(content.makeImage()!, in: CGRect(x: 0, y: 0, width: card.width, height: card.height))
ctx.restoreGState()

// 비교 핸들: 세로선 + 원 + 좌우 화살표.
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fill(CGRect(x: 512 - 7, y: card.minY, width: 14, height: card.height))
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
ctx.fillEllipse(in: CGRect(x: 512 - 78, y: 512 - 78, width: 156, height: 156))
ctx.setShadow(offset: .zero, blur: 0)
// 바깥을 향한 채운 삼각형 두 개(◀ ▶). 꺾쇠(< >)는 코드 아이콘처럼 읽힌다.
ctx.setFillColor(rgb(0x5B67D8))
ctx.setStrokeColor(rgb(0x5B67D8))
ctx.setLineWidth(8)
ctx.setLineJoin(.round)
for dir in [-1.0, 1.0] {
    ctx.move(to: CGPoint(x: 512 + dir * 12, y: 482))
    ctx.addLine(to: CGPoint(x: 512 + dir * 50, y: 512))
    ctx.addLine(to: CGPoint(x: 512 + dir * 12, y: 542))
    ctx.closePath()
}
ctx.drawPath(using: .fillStroke)

// 카메라 뷰파인더 모서리.
ctx.setStrokeColor(rgb(0xA8B8FF))
ctx.setLineWidth(26)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let inset: CGFloat = 150, arm: CGFloat = 120
for (cx, cy, dx, dy) in [(inset, inset, 1.0, 1.0), (s - inset, inset, -1.0, 1.0), (inset, s - inset, 1.0, -1.0), (s - inset, s - inset, -1.0, -1.0)] {
    ctx.move(to: CGPoint(x: cx, y: cy + dy * arm))
    ctx.addLine(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx + dx * arm, y: cy))
}
ctx.strokePath()

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
print("wrote", out.path)
