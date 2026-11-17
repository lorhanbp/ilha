// Desenha o logo da Ilha (uma ilha com palmeira sob o notch) e salva em PNG.
// Uso: swift scripts/make-icon.swift assets/logo.png
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// Fundo: quadrado arredondado, céu da noite que clareia até o mar
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let shape = CGPath(roundedRect: rect, cornerWidth: 230, cornerHeight: 230, transform: nil)
ctx.addPath(shape); ctx.clip()
gradient([color(0x070B22), color(0x14346B), color(0x2E86AB)], from: CGPoint(x: 0, y: size), to: CGPoint(x: 0, y: 0))

// Lua com brilho
let moon = CGPoint(x: 790, y: 740)
let glow = CGGradient(colorsSpace: space, colors: [color(0xFFE9B8, 0.55), color(0xFFE9B8, 0)] as CFArray, locations: nil)!
ctx.drawRadialGradient(glow, startCenter: moon, startRadius: 0, endCenter: moon, endRadius: 210, options: [])
ctx.setFillColor(color(0xFFF2D2))
ctx.fillEllipse(in: CGRect(x: moon.x - 62, y: moon.y - 62, width: 124, height: 124))

// Estrelas
ctx.setFillColor(color(0xFFFFFF, 0.8))
for (x, y, r) in [(210.0, 760.0, 7.0), (330, 640, 5), (470, 800, 6), (150, 600, 4), (640, 840, 5), (900, 590, 5)] {
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// Mar atrás da ilha
ctx.setFillColor(color(0x0D2D5A, 0.55))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: 330))

// Ilha de areia
let island = CGMutablePath()
island.move(to: CGPoint(x: 170, y: 300))
island.addCurve(to: CGPoint(x: 860, y: 300), control1: CGPoint(x: 280, y: 520), control2: CGPoint(x: 720, y: 540))
island.closeSubpath()
ctx.saveGState()
ctx.addPath(island); ctx.clip()
gradient([color(0xF7DDA0), color(0xD8A55A)], from: CGPoint(x: 0, y: 470), to: CGPoint(x: 0, y: 300))
ctx.restoreGState()

// Palmeira: tronco curvo
let trunk = CGMutablePath()
trunk.move(to: CGPoint(x: 520, y: 430))
trunk.addCurve(to: CGPoint(x: 610, y: 690), control1: CGPoint(x: 500, y: 540), control2: CGPoint(x: 560, y: 630))
ctx.setLineCap(.round)
ctx.setStrokeColor(color(0x6B4423)); ctx.setLineWidth(38); ctx.addPath(trunk); ctx.strokePath()
ctx.setStrokeColor(color(0x8C5E34)); ctx.setLineWidth(14); ctx.addPath(trunk); ctx.strokePath()

// Folhas
func frond(angle: CGFloat, length: CGFloat, base: CGPoint, tone: UInt32) {
    ctx.saveGState()
    ctx.translateBy(x: base.x, y: base.y)
    ctx.rotate(by: angle * .pi / 180)
    let leaf = CGMutablePath()
    leaf.move(to: .zero)
    leaf.addCurve(to: CGPoint(x: length, y: -length * 0.18), control1: CGPoint(x: length * 0.3, y: length * 0.3), control2: CGPoint(x: length * 0.75, y: length * 0.22))
    leaf.addCurve(to: .zero, control1: CGPoint(x: length * 0.7, y: -length * 0.05), control2: CGPoint(x: length * 0.3, y: length * 0.02))
    ctx.setFillColor(color(tone))
    ctx.addPath(leaf); ctx.fillPath()
    ctx.restoreGState()
}
let crown = CGPoint(x: 610, y: 690)
for (angle, length, tone) in [(165.0, 250.0, 0x1F7A4D), (130, 270, 0x2A9461), (95, 235, 0x1F7A4D), (50, 270, 0x2A9461), (15, 250, 0x1F7A4D), (-20, 215, 0x176B42)] {
    frond(angle: angle, length: length, base: crown, tone: UInt32(tone))
}
ctx.setFillColor(color(0x8C5E34))
ctx.fillEllipse(in: CGRect(x: crown.x - 24, y: crown.y - 22, width: 48, height: 48))

// Ondas na frente
ctx.setStrokeColor(color(0xBFE8F5, 0.85)); ctx.setLineWidth(14)
for (y, offset) in [(250.0, 0.0), (180.0, 60.0), (110.0, 20.0)] {
    let wave = CGMutablePath()
    var x: CGFloat = -40 + CGFloat(offset)
    wave.move(to: CGPoint(x: x, y: y))
    while x < size + 60 {
        wave.addQuadCurve(to: CGPoint(x: x + 80, y: y), control: CGPoint(x: x + 40, y: y + 36))
        x += 80
        wave.addQuadCurve(to: CGPoint(x: x + 80, y: y), control: CGPoint(x: x + 40, y: y - 36))
        x += 80
    }
    ctx.addPath(wave); ctx.strokePath()
}

// O notch, pendurado no topo: a "ilha dinâmica"
let notch = CGMutablePath()
notch.addRoundedRect(in: CGRect(x: 332, y: 880, width: 360, height: 200), cornerWidth: 70, cornerHeight: 70)
ctx.setFillColor(color(0x000000)); ctx.addPath(notch); ctx.fillPath()
ctx.setFillColor(color(0x14346B, 0.9))
ctx.fillEllipse(in: CGRect(x: 585, y: 925, width: 34, height: 34))

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.dropFirst().first ?? "logo.png"
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("ok:", out)
