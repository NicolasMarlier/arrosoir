import SwiftUI

/// Illustration « papier découpé » d'une plante avec une tête sur le pot.
/// Coordonnées dans un repère 100×100 (portées depuis les maquettes SVG).
struct PlantIllustration: View {
    let archetype: PlantArchetype
    let mood: Mood
    let pot: PotStyle

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            ctx.translateBy(x: (size.width - 100 * s) / 2, y: (size.height - 100 * s) / 2)
            ctx.scaleBy(x: s, y: s)
            var d = Drawer(ctx: ctx, palette: IllustrationPalette(mood: mood))
            d.drawPot(pot, ghost: mood == .ghost)
            PlantDrawings.draw(archetype, &d, mood: mood)
            d.drawFace(mood: mood, lightFace: mood == .ghost ? false : pot.lightFace)
            d.drawDeco(mood: mood)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

extension PlantIllustration {
    init(plant: Plant, mood: Mood) {
        self.init(archetype: plant.archetype, mood: mood, pot: plant.potStyle)
    }
}

// MARK: - Palette

struct IllustrationPalette {
    var leaf: Color
    var leaf2: Color
    var leafLight: Color
    var stem: Color
    var flower: Color
    var flowerCenter: Color
    var trap: Color
    var trunk: Color
    var edge: Color
    var slit: Color = .white
    var water: Color = .cobalt
    var spark: Color = .mustard

    init(mood: Mood) {
        let ghost = mood == .ghost
        let grey = Color(hex: 0xCFC9D8)
        leaf = switch mood {
        case .thirsty: Color(hex: 0xC2A53A)
        case .sleeping: Color(hex: 0x5F9B78)
        case .ghost: Color(hex: 0xBDB7C9)
        default: .leafGreen
        }
        leafLight = switch mood {
        case .thirsty: Color(hex: 0xD9C25A)
        case .sleeping: Color(hex: 0x86B79A)
        case .ghost: Color(hex: 0xD3CEDC)
        default: Color(hex: 0x4FB06F)
        }
        leaf2 = ghost ? Color(hex: 0xA29CB0) : .leafDark
        stem = leaf2
        flower = ghost ? grey : .pinkFlower
        flowerCenter = ghost ? grey : .mustard
        trap = ghost ? grey : .vermillon
        trunk = ghost ? grey : Color(hex: 0xC9732F)
        edge = ghost ? grey : .mustard
    }
}

// MARK: - Dessin

struct Drawer {
    var ctx: GraphicsContext
    let palette: IllustrationPalette
    var transform: CGAffineTransform = .identity

    static let heart = Path(svg: "M0 14 C -14 6 -16 -10 -6 -14 C -2 -15 0 -12 0 -10 C 0 -12 2 -15 6 -14 C 16 -10 14 6 0 14 Z")
    static let drop = Path(svg: "M0 -7 C 4 -1 5 2 0 6 C -5 2 -4 -1 0 -7 Z")
    static let spark = Path(svg: "M0 -6 Q1 -1 6 0 Q1 1 0 6 Q-1 1 -6 0 Q-1 -1 0 -6 Z")

    func fill(_ p: Path, _ c: Color) {
        ctx.fill(p.applying(transform), with: .color(c))
    }

    func stroke(_ p: Path, _ c: Color, _ w: CGFloat) {
        ctx.stroke(p.applying(transform), with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }

    func fill(svg: String, _ c: Color) { fill(Path(svg: svg), c) }
    func stroke(svg: String, _ c: Color, _ w: CGFloat) { stroke(Path(svg: svg), c, w) }

    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rot: CGFloat = 0, _ c: Color) {
        group(cx, cy, 1, rot) { d in
            d.fill(Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)), c)
        }
    }

    func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c: Color) {
        fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), c)
    }

    func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ c: Color, _ w: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2, y: y2))
        stroke(p, c, w)
    }

    /// Équivalent SVG de `translate(x y) rotate(r) scale(s)`.
    func group(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ rot: CGFloat, _ body: (Drawer) -> Void) {
        var d = self
        d.transform = CGAffineTransform(translationX: x, y: y)
            .rotated(by: rot * .pi / 180)
            .scaledBy(x: s, y: s)
            .concatenating(transform)
        body(d)
    }

    func heart(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ rot: CGFloat, _ c: Color, details: ((Drawer) -> Void)? = nil) {
        group(x, y, s, rot) { d in
            d.fill(Drawer.heart, c)
            details?(d)
        }
    }

    func flower(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ rot: CGFloat, petal: Color, center: Color, rx: CGFloat = 3, ry: CGFloat = 4.6) {
        group(x, y, s, rot) { d in
            for a in stride(from: 0.0, to: 360.0, by: 72.0) {
                d.group(0, 0, 1, a) { d2 in
                    d2.fill(Path(ellipseIn: CGRect(x: -rx, y: -4.5 - ry, width: rx * 2, height: ry * 2)), petal)
                }
            }
            d.fill(Path(ellipseIn: CGRect(x: -2, y: -2, width: 4, height: 4)), center)
        }
    }

    // MARK: Pot, visage, décor

    func drawPot(_ pot: PotStyle, ghost: Bool) {
        fill(svg: "M30 70 L70 70 L65.5 96 L34.5 96 Z", ghost ? Color(hex: 0xD9D4E0) : Color(hex: pot.pot))
        fill(Path(roundedRect: CGRect(x: 27, y: 64, width: 46, height: 9), cornerRadius: 3), ghost ? Color(hex: 0xC7C1CF) : Color(hex: pot.rim))
    }

    /// Visage « yeux découpés » (variante B validée).
    func drawFace(mood: Mood, lightFace: Bool) {
        let ink: Color = lightFace ? .cream : .ink
        let ex: [CGFloat] = [43.5, 56.5]
        let ey: CGFloat = 80.5

        switch mood {
        case .sleeping, .ghost:
            for x in ex { stroke(svg: "M\(x - 3) \(ey) Q\(x) \(ey + 3.5) \(x + 3) \(ey)", ink, 1.9) }
        case .happy:
            for x in ex { stroke(svg: "M\(x - 3) \(ey + 1.5) Q\(x) \(ey - 2.5) \(x + 3) \(ey + 1.5)", ink, 1.9) }
        case .ok, .thirsty:
            let py: CGFloat = mood == .thirsty ? -1.6 : 0.4
            let px: CGFloat = mood == .thirsty ? 0.8 : 0
            for x in ex {
                circle(x, ey, 4.6, .white)
                circle(x + px, ey + py, 2.2, .ink)
            }
        }
        if mood == .thirsty {
            stroke(svg: "M38.5 74 L46 75.8 M61.5 74 L54 75.8", ink, 1.8)
        }
        switch mood {
        case .ok: stroke(svg: "M46.5 87.5 Q50 91 53.5 87.5", ink, 1.9)
        case .thirsty: ellipse(50, 89, 2, 2.6, ink)
        case .sleeping: line(48, 89, 52, 89, ink, 1.9)
        case .happy: fill(svg: "M45.5 87 Q50 93.5 54.5 87 Z", ink)
        case .ghost: stroke(svg: "M47.5 89.5 Q50 88 52.5 89.5", ink, 1.6)
        }
    }

    func drawDeco(mood: Mood) {
        switch mood {
        case .thirsty:
            group(85, 15, 1, 0) { $0.fill(Drawer.drop, palette.water) }
            group(92, 28, 0.6, 0) { $0.fill(Drawer.drop, palette.water) }
        case .sleeping:
            ctx.draw(Text("z").font(.custom(BricoWeight.heavy.rawValue, size: 11)).foregroundStyle(palette.water), at: CGPoint(x: 79, y: 18))
            ctx.draw(Text("Z").font(.custom(BricoWeight.heavy.rawValue, size: 16)).foregroundStyle(palette.water), at: CGPoint(x: 89, y: 9))
        case .happy:
            group(16, 22, 1, 0) { $0.fill(Drawer.spark, palette.spark) }
            group(86, 16, 1.2, 0) { $0.fill(Drawer.spark, palette.spark) }
            group(88, 40, 0.7, 0) { $0.fill(Drawer.spark, palette.spark) }
            group(14, 44, 0.6, 0) { $0.fill(Drawer.drop, palette.water) }
        case .ghost:
            ctx.stroke(Path(ellipseIn: CGRect(x: 37, y: 5.4, width: 26, height: 7.2)), with: .color(.mustard), lineWidth: 2.5)
        case .ok:
            break
        }
    }
}

// MARK: - Mini parseur SVG (commandes absolues M L Q C Z)

extension Path {
    init(svg: String) {
        self.init()
        var tokens: [String] = []
        var current = ""
        for ch in svg {
            if ch.isLetter {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if ch == "-" && !current.isEmpty && current.last != "e" {
                tokens.append(current); current = "-"
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var i = 0
        var cmd = "M"
        func num() -> CGFloat {
            defer { i += 1 }
            return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0
        }
        func pt() -> CGPoint { CGPoint(x: num(), y: num()) }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter {
                cmd = String(c)
                i += 1
                if cmd == "Z" || cmd == "z" { closeSubpath(); continue }
            }
            switch cmd {
            case "M": move(to: pt()); cmd = "L"
            case "L": addLine(to: pt())
            case "Q": let c = pt(); addQuadCurve(to: pt(), control: c)
            case "C": let c1 = pt(); let c2 = pt(); addCurve(to: pt(), control1: c1, control2: c2)
            default: i += 1
            }
        }
    }
}
