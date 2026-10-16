// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
// Puts a device screenshot in a drawn phone, on the teal-to-plum background, under a headline: the pictures in the README and on the website.
//   swift tools/frame_screenshot.swift <screenshot.png> <out.jpg> "<headline>" "<subtitle>"
// The orientation follows the screenshot. Portrait output is 828x1800, landscape 1800x828.
import AppKit

let args = CommandLine.arguments
guard args.count == 5, let shot = NSImage(contentsOfFile: args[1]) else { print("usage: frame_screenshot.swift in.png out.jpg headline subtitle"); exit(1) }
let rep = shot.representations.first!
let sw = CGFloat(rep.pixelsWide), sh = CGFloat(rep.pixelsHigh)
let landscape = sw > sh
let W: CGFloat = landscape ? 1800 : 828, H: CGFloat = landscape ? 828 : 1800

let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Work top-left origin like a picture.
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

// Background.
let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
    CGColor(red: 0.055, green: 0.33, blue: 0.38, alpha: 1), CGColor(red: 0.10, green: 0.16, blue: 0.30, alpha: 1), CGColor(red: 0.30, green: 0.12, blue: 0.30, alpha: 1)] as CFArray,
    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: W, y: H), options: [])

// The phone.
let bezel: CGFloat = 16
let phone: CGRect
if landscape { let w: CGFloat = 1185, h = (w - 2 * bezel) * sh / sw + 2 * bezel; phone = CGRect(x: W - w - 42, y: (H - h) / 2, width: w, height: h) }
else { let w: CGFloat = 622, h = (w - 2 * bezel) * sh / sw + 2 * bezel; phone = CGRect(x: (W - w) / 2, y: H - h - 70, width: w, height: h) }
let outerR: CGFloat = landscape ? 78 : 92, innerR = outerR - bezel
// Shadow, body, rim.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 24), blur: 60, color: CGColor(gray: 0, alpha: 0.5))
ctx.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1))
ctx.addPath(CGPath(roundedRect: phone, cornerWidth: outerR, cornerHeight: outerR, transform: nil)); ctx.fillPath()
ctx.restoreGState()
ctx.setStrokeColor(CGColor(red: 0.45, green: 0.45, blue: 0.52, alpha: 0.9)); ctx.setLineWidth(3)
ctx.addPath(CGPath(roundedRect: phone.insetBy(dx: 1.5, dy: 1.5), cornerWidth: outerR, cornerHeight: outerR, transform: nil)); ctx.strokePath()
// Screen.
let screen = phone.insetBy(dx: bezel, dy: bezel)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: screen, cornerWidth: innerR, cornerHeight: innerR, transform: nil)); ctx.clip()
let cg = shot.cgImage(forProposedRect: nil, context: nil, hints: nil)!
ctx.saveGState(); ctx.translateBy(x: screen.minX, y: screen.maxY); ctx.scaleBy(x: 1, y: -1)   // CGContext images draw bottom-up
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: screen.width, height: screen.height)); ctx.restoreGState()
ctx.restoreGState()
// Dynamic island: the iPhone 15 Pro Max's is 372 x 111 device pixels, 33 down from the edge (on its left edge when the phone is held sideways).
let unit = screen.width / sw
let islandLong = 372 * unit, islandShort = 111 * unit, islandInset = 33 * unit
let island = landscape ? CGRect(x: screen.minX + islandInset, y: screen.midY - islandLong / 2, width: islandShort, height: islandLong)
                       : CGRect(x: screen.midX - islandLong / 2, y: screen.minY + islandInset, width: islandLong, height: islandShort)
ctx.setFillColor(CGColor(gray: 0, alpha: 1))
ctx.addPath(CGPath(roundedRect: island, cornerWidth: islandShort / 2, cornerHeight: islandShort / 2, transform: nil)); ctx.fillPath()

// Headline and subtitle: the block is measured, so a headline of one or two lines keeps the subtitle just under it.
func attributed(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSAttributedString {
    let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping; style.lineSpacing = size * 0.06
    return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                         .foregroundColor: NSColor.white.withAlphaComponent(alpha), .paragraphStyle: style])
}
let textWidth: CGFloat = landscape ? 480 : 720
let head = attributed(args[3], size: landscape ? 66 : 62, weight: .bold, alpha: 1)
let sub = attributed(args[4], size: landscape ? 34 : 33, weight: .regular, alpha: 0.82)
func height(_ t: NSAttributedString) -> CGFloat { ceil(t.boundingRect(with: CGSize(width: textWidth, height: 1000), options: [.usesLineFragmentOrigin]).height) }
let gap: CGFloat = 18
let block = height(head) + gap + height(sub)
let x: CGFloat = landscape ? 62 : 58
var y: CGFloat = landscape ? (H - block) / 2 : 84
head.draw(in: CGRect(x: x, y: y, width: textWidth, height: height(head) + 4)); y += height(head) + gap
sub.draw(in: CGRect(x: x, y: y, width: textWidth, height: height(sub) + 4))

let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
let data = out.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
try data.write(to: URL(fileURLWithPath: args[2]))
print("wrote", args[2])
