import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a])!
}
func grad(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}
func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }
func arcPoints(_ c: CGPoint, _ r: CGFloat, _ from: CGFloat, _ to: CGFloat) -> [CGPoint] {
    stride(from: from, through: to, by: 1).map { d in CGPoint(x: c.x + r * cos(d * .pi / 180), y: c.y + r * sin(d * .pi / 180)) }
}
let cyan: UInt32 = 0x1FD6EA

func render(_ variant: String, to out: String) {
    let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: (["M", "WS", "WN"].contains(variant) ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(S)); ctx.scaleBy(x: 1, y: -1)
    let C = CGPoint(x: 512, y: 512)
    let mark = ["M", "WS", "WN"].contains(variant)       // M: the in-app mark; WS / WN: larger, for the website (sunset / night)
    let sunset = variant == "V2" || variant == "M" || variant == "WS"
    let night = ["N", "T", "WN"].contains(variant)

    if !mark {
    // Background: deep teal-navy, so the silver stands out.
    ctx.drawLinearGradient(grad(night ? [(0, rgb(0x08202C)), (1, rgb(0x01070C))] : [(0, rgb(0x0E3646)), (1, rgb(0x03111B))]), start: .zero, end: CGPoint(x: S, y: S), options: [])
    ctx.drawRadialGradient(grad([(0, rgb(cyan, 0.26)), (1, rgb(cyan, 0))]), startCenter: C, startRadius: 0, endCenter: C, endRadius: 620, options: [])

    }

    // The silver porthole.
    let ring = CGMutablePath(); ring.addEllipse(in: circle(C, 404)); ring.addEllipse(in: circle(C, 322))
    ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 40, color: rgb(0x000000, 0.45))
    ctx.addPath(ring); ctx.setFillColor(rgb(0xC9D2DC)); ctx.fillPath(using: .evenOdd); ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(ring); ctx.clip(using: .evenOdd)
    ctx.drawLinearGradient(grad([(0, rgb(0xFFFFFF)), (0.28, rgb(0xDDE5ED)), (0.55, rgb(0xA9B6C4)), (0.8, rgb(0xC7D1DB)), (1, rgb(0x6F7E90))]),
                           start: CGPoint(x: 200, y: 140), end: CGPoint(x: 840, y: 900), options: [])
    // A bevel: the outer lip lighter, a groove in the middle of the band.
    ctx.restoreGState()
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.9)); ctx.setLineWidth(5)
    ctx.addEllipse(in: circle(C, 400)); ctx.strokePath()
    ctx.setStrokeColor(rgb(0x4B5A6B, 0.35)); ctx.setLineWidth(3)
    ctx.addEllipse(in: circle(C, 363 + 40)); ctx.strokePath()
    ctx.setStrokeColor(rgb(0x4B5A6B, 0.45)); ctx.setLineWidth(10)
    ctx.addEllipse(in: circle(C, 326)); ctx.strokePath()
    ctx.setStrokeColor(rgb(cyan, 0.5)); ctx.setLineWidth(4)
    ctx.addEllipse(in: circle(C, 320)); ctx.strokePath()
    // Bolts.
    for k in 0..<8 {
        let a = (CGFloat(k) * 45 + 22.5) * .pi / 180
        let p = CGPoint(x: C.x + 363 * cos(a), y: C.y + 363 * sin(a))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 6, color: rgb(0x1B2733, 0.55))
        ctx.addEllipse(in: circle(p, 20)); ctx.clip()
        ctx.drawRadialGradient(grad([(0, rgb(0xFFFFFF)), (0.5, rgb(0xB9C5D2)), (1, rgb(0x56667A))]),
                               startCenter: CGPoint(x: p.x - 6, y: p.y - 7), startRadius: 0, endCenter: p, endRadius: 26, options: [])
        ctx.restoreGState()
        // a slot, so it is a screw and not a dot
        ctx.setStrokeColor(rgb(0x3B4A5C, 0.7)); ctx.setLineWidth(3.5)
        ctx.move(to: CGPoint(x: p.x - 9 * cos(a + .pi / 4), y: p.y - 9 * sin(a + .pi / 4)))
        ctx.addLine(to: CGPoint(x: p.x + 9 * cos(a + .pi / 4), y: p.y + 9 * sin(a + .pi / 4))); ctx.strokePath()
    }

    if night { ctx.saveGState(); ctx.addPath(ring); ctx.clip(using: .evenOdd); ctx.setFillColor(rgb(0x04121C, 0.28)); ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(S), height: CGFloat(S))); ctx.restoreGState() }
    // The view.
    let horizon: CGFloat = 566
    ctx.saveGState(); ctx.addEllipse(in: circle(C, 320)); ctx.clip()
    // Sky.
    if night {
        ctx.drawLinearGradient(grad([(0, rgb(0x01060F)), (0.5, rgb(0x053049)), (1, rgb(0x14A3BD))]), start: CGPoint(x: 0, y: 190), end: CGPoint(x: 0, y: horizon), options: [])
        // Stars.
        let stars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(250,300,2.6,0.9),(300,230,2,0.7),(380,210,3,0.95),(450,260,2,0.6),(520,200,2.4,0.8),(560,262,1.8,0.6),
            (700,220,2.6,0.9),(760,300,2,0.7),(800,380,2.4,0.8),(270,380,1.8,0.6),(330,330,2.2,0.7),(740,450,1.8,0.55),(470,420,1.6,0.5),(600,420,2,0.6),(820,250,1.8,0.6),(210,440,1.8,0.55),(560,350,1.6,0.55)]
        for (x, y, r, a) in stars { ctx.setFillColor(rgb(0xE8FBFF, a)); ctx.addEllipse(in: circle(CGPoint(x: x, y: y), r)); ctx.fillPath() }
        // Two sparkles.
        for (x, y, r) in [(CGFloat(640), CGFloat(500), CGFloat(13)), (CGFloat(250), CGFloat(500), CGFloat(9))] {
            ctx.setStrokeColor(rgb(0xFFFFFF, 0.85)); ctx.setLineWidth(3); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: x - r, y: y)); ctx.addLine(to: CGPoint(x: x + r, y: y))
            ctx.move(to: CGPoint(x: x, y: y - r)); ctx.addLine(to: CGPoint(x: x, y: y + r)); ctx.strokePath()
        }
        // The moon: a crescent, lit on its lower left, with a soft glow around it.
        let moonC = CGPoint(x: 662, y: 336)
        ctx.drawRadialGradient(grad([(0, rgb(0xBFEFFF, 0.42)), (1, rgb(0xBFEFFF, 0))]), startCenter: moonC, startRadius: 0, endCenter: moonC, endRadius: 150, options: [])
        ctx.saveGState()
        ctx.addEllipse(in: circle(moonC, 68)); ctx.clip()
        let bite = CGMutablePath()
        bite.addRect(CGRect(x: 0, y: 0, width: CGFloat(S), height: CGFloat(S)))
        bite.addEllipse(in: circle(CGPoint(x: moonC.x + 30, y: moonC.y - 20), 58))
        ctx.addPath(bite); ctx.clip(using: .evenOdd)
        ctx.drawLinearGradient(grad([(0, rgb(0xFFFFFF)), (1, rgb(0xE6EDCB))]), start: CGPoint(x: moonC.x + 40, y: moonC.y - 70), end: CGPoint(x: moonC.x - 50, y: moonC.y + 60), options: [])
        ctx.restoreGState()
        // A shooting star: a tapering tail and a bright head.
        let head = CGPoint(x: 548, y: 292), tail = CGPoint(x: 392, y: 212)
        let dx = head.x - tail.x, dy = head.y - tail.y, len = hypot(dx, dy)
        let nx = -dy / len * 7, ny = dx / len * 7
        ctx.saveGState()
        let streak = CGMutablePath()
        streak.move(to: tail); streak.addLine(to: CGPoint(x: head.x + nx, y: head.y + ny)); streak.addLine(to: CGPoint(x: head.x - nx, y: head.y - ny)); streak.closeSubpath()
        ctx.addPath(streak); ctx.clip()
        ctx.drawLinearGradient(grad([(0, rgb(0xFFFFFF, 0)), (1, rgb(0xFFFFFF, 0.95))]), start: tail, end: head, options: [])
        ctx.restoreGState()
        ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 30, color: rgb(0xBFF6FF, 0.95))
        ctx.addEllipse(in: circle(head, 12)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath(); ctx.restoreGState()
    } else {
        if sunset {
            ctx.drawLinearGradient(grad([(0, rgb(0x0B4F6B)), (0.55, rgb(0x3FB7C9)), (0.85, rgb(0xFFC9A0)), (1, rgb(0xFFE3B0))]), start: CGPoint(x: 0, y: 190), end: CGPoint(x: 0, y: horizon), options: [])
        } else {
            ctx.drawLinearGradient(grad([(0, rgb(0x0A6E92)), (0.6, rgb(0x4CD6EE)), (1, rgb(0xCFFBFF))]), start: CGPoint(x: 0, y: 190), end: CGPoint(x: 0, y: horizon), options: [])
        }
        let sunC = CGPoint(x: 618, y: horizon - 18)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 70, color: rgb(sunset ? 0xFF8A3D : 0xFFD36B, 0.85))
        ctx.addEllipse(in: circle(sunC, 66)); ctx.setFillColor(rgb(0xFFC25A)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addEllipse(in: circle(sunC, 66)); ctx.clip()
        ctx.drawLinearGradient(grad([(0, rgb(0xFFF0A0)), (1, rgb(sunset ? 0xFF7A45 : 0xFFB347))]), start: CGPoint(x: 0, y: sunC.y - 66), end: CGPoint(x: 0, y: sunC.y + 66), options: [])
        ctx.restoreGState()
    }
    // Sea: cyan, brighter at the horizon.
    ctx.drawLinearGradient(grad(night ? [(0, rgb(0x19B5CF)), (0.2, rgb(0x0A7C9B)), (0.7, rgb(0x064B66)), (1, rgb(0x021B27))] : [(0, rgb(0x6FF1FF)), (0.2, rgb(cyan)), (0.7, rgb(0x0B9DBE)), (1, rgb(0x05607B))]), start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: 860), options: [])
    ctx.setFillColor(rgb(0xFFFFFF, 0.65)); ctx.fill(CGRect(x: 0, y: horizon - 1.5, width: CGFloat(S), height: 3))
    // The sun on the water.
    let sunC = CGPoint(x: night ? 662 : 618, y: horizon - 18)
    var dy = horizon + 16
    for (w, h) in [(120, 9), (96, 10), (70, 11), (46, 12)] as [(CGFloat, CGFloat)] {
        ctx.setFillColor(rgb(night ? 0xEAF8F0 : (sunset ? 0xFFB070 : 0xFFE9A0), night ? 0.8 : 0.9))
        ctx.addPath(CGPath(roundedRect: CGRect(x: sunC.x - w / 2, y: dy, width: w, height: h), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)); ctx.fillPath()
        dy += h + 17
    }
    // Wave glints.
    ctx.setFillColor(rgb(0xFFFFFF, 0.45))
    for (x, y, w) in [(330, 600, 70), (440, 640, 90), (360, 700, 120), (470, 760, 150), (300, 790, 100), (720, 640, 80), (700, 720, 110), (640, 800, 130)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: 8), cornerWidth: 4, cornerHeight: 4, transform: nil))
    }
    ctx.fillPath()

    // The island, small and far away, with one palm.
    let isle = CGMutablePath()
    isle.move(to: CGPoint(x: 280, y: horizon + 1))
    isle.addCurve(to: CGPoint(x: 372, y: horizon - 44), control1: CGPoint(x: 306, y: horizon - 6), control2: CGPoint(x: 336, y: horizon - 38))
    isle.addCurve(to: CGPoint(x: 438, y: horizon - 34), control1: CGPoint(x: 394, y: horizon - 54), control2: CGPoint(x: 418, y: horizon - 50))
    isle.addCurve(to: CGPoint(x: 520, y: horizon + 1), control1: CGPoint(x: 466, y: horizon - 22), control2: CGPoint(x: 494, y: horizon - 8))
    isle.closeSubpath()
    ctx.saveGState()
    ctx.addPath(isle); ctx.clip()
    ctx.drawLinearGradient(grad(night ? [(0, rgb(0x06303A)), (1, rgb(0x021218))] : [(0, rgb(0x137A74)), (1, rgb(0x053A45))]), start: CGPoint(x: 0, y: horizon - 56), end: CGPoint(x: 0, y: horizon), options: [])
    ctx.restoreGState()
    // Palm: a curved trunk and five fronds.
    let base = CGPoint(x: 404, y: horizon - 44)
    let top = CGPoint(x: 424, y: horizon - 112)
    ctx.setStrokeColor(rgb(night ? 0x021A20 : 0x063A40)); ctx.setLineWidth(9); ctx.setLineCap(.round)
    ctx.move(to: base); ctx.addQuadCurve(to: top, control: CGPoint(x: 396, y: horizon - 84)); ctx.strokePath()
    ctx.setStrokeColor(rgb(night ? 0x053238 : 0x0C6B66)); ctx.setLineWidth(8)
    for (dx, dy2) in [(-52, 14), (-34, -18), (0, -30), (36, -16), (54, 16)] as [(CGFloat, CGFloat)] {
        ctx.move(to: top)
        ctx.addQuadCurve(to: CGPoint(x: top.x + dx, y: top.y + dy2 + 14), control: CGPoint(x: top.x + dx * 0.55, y: top.y + dy2 - 22))
        ctx.strokePath()
    }
    // Light through the glass.
    ctx.setFillColor(rgb(0xFFFFFF, 0.07))
    ctx.move(to: CGPoint(x: 300, y: 170)); ctx.addLine(to: CGPoint(x: 470, y: 170)); ctx.addLine(to: CGPoint(x: 600, y: 880)); ctx.addLine(to: CGPoint(x: 380, y: 880)); ctx.fillPath()
    ctx.restoreGState()
    // Reflection on the glass.
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.5)); ctx.setLineWidth(22); ctx.setLineCap(.round)
    ctx.addLines(between: arcPoints(C, 272, 205, 252)); ctx.strokePath()

    var image = ctx.makeImage()!
    if mark {
        let cropped = image.cropping(to: CGRect(x: 100, y: 100, width: 824, height: 824))!
        let px = variant == "M" ? 360 : 800
        let small = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        small.interpolationQuality = .high
        small.draw(cropped, in: CGRect(x: 0, y: 0, width: px, height: px))
        image = small.makeImage()!
    }
    if variant == "T" {
        let g = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        g.draw(image, in: CGRect(x: 0, y: 0, width: S, height: S))
        image = g.makeImage()!
    }
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
for v in ["V2", "N", "T", "M", "WS", "WN"] { render(v, to: "icon-\(v).png") }
print("ok")
