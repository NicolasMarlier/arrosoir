import SwiftUI

/// Une fonction de dessin par famille de plantes. Base des tiges vers (50, 66), juste au-dessus du pot.
enum PlantDrawings {
    static func draw(_ a: PlantArchetype, _ d: inout Drawer, mood: Mood) {
        let p = d.palette
        let blooming = mood != .sleeping && mood != .ghost
        switch a {
        case .monstera: monstera(d, p)
        case .trailing: trailing(d, p)
        case .cactus: cactus(d, p, blooming: blooming)
        case .carnivorous: carnivorous(d, p)
        case .upright: upright(d, p)
        case .caudex: caudex(d, p, blooming: blooming)
        case .succulent: succulent(d, p)
        case .sword: sword(d, p)
        case .tree: tree(d, p)
        case .fern: fern(d, p)
        case .orchid: orchid(d, p, blooming: blooming)
        }
    }

    static func monstera(_ d: Drawer, _ p: IllustrationPalette) {
        let leaves: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(33, 34, 1.45, 150), (63, 27, 1.55, 200), (74, 48, 1.15, 235), (36, 52, 1.05, 125)]
        for (x, y, _, _) in leaves {
            d.stroke(svg: "M50 66 Q \((x + 50) / 2) \(y + 18) \(x) \(y)", p.stem, 2.4)
        }
        for (x, y, s, r) in leaves {
            d.heart(x, y, s, r, p.leaf) { l in
                l.stroke(svg: "M-2 -3 L-11 -6 M-2 3 L-10 4 M-1 8 L-6 10 M2 -3 L11 -6 M2 3 L10 4 M1 8 L6 10", p.slit, 1.8)
            }
        }
    }

    static func trailing(_ d: Drawer, _ p: IllustrationPalette) {
        d.stroke(svg: "M34 66 C 26 70 20 80 22 94", p.stem, 1.6)
        d.stroke(svg: "M66 66 C 76 72 80 82 78 94", p.stem, 1.6)
        for (x, y, s, r) in [(38.0, 54.0, 0.85, 160.0), (52, 47, 0.95, 185), (63, 56, 0.85, 215), (46, 60, 0.7, 150)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            d.heart(x, y, s, r, p.leaf) { l in
                l.stroke(svg: "M-3 -4 Q 0 2 -2 8 M4 -6 Q 3 0 5 5", p.leaf2, 1.6)
            }
        }
        for (x, y, s, r) in [(25.0, 76.0, 0.6, 20.0), (21, 89, 0.55, -10), (75, 77, 0.6, -25), (79, 90, 0.55, 10)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            d.heart(x, y, s, r, p.leaf)
        }
    }

    static func cactus(_ d: Drawer, _ p: IllustrationPalette, blooming: Bool) {
        let rects: [CGRect] = [
            CGRect(x: 29, y: 33, width: 9, height: 20), CGRect(x: 31, y: 45, width: 15, height: 8),
            CGRect(x: 62, y: 27, width: 9, height: 18), CGRect(x: 55, y: 38, width: 15, height: 8),
            CGRect(x: 41, y: 20, width: 18, height: 48),
        ]
        for r in rects {
            d.fill(Path(roundedRect: r, cornerRadius: min(r.width, r.height) / 2), p.leaf)
        }
        d.stroke(svg: "M46 26 L46 62 M50 23 L50 64 M54 26 L54 62", p.leaf2, 1.3)
        if blooming { d.flower(50, 19, 1, 0, petal: p.flower, center: p.flowerCenter, rx: 2.6, ry: 4) }
    }

    static func carnivorous(_ d: Drawer, _ p: IllustrationPalette) {
        d.ellipse(50, 64, 18, 5, p.leaf)
        let traps: [(CGFloat, CGFloat, CGFloat)] = [(27, 46, -55), (38, 32, -25), (62, 32, 25), (73, 46, 55), (50, 24, 0)]
        for (x, y, _) in traps { d.line(50, 63, x, y + 6, p.leaf, 3.2) }
        for (x, y, r) in traps {
            d.group(x, y, 1, r) { t in
                t.fill(svg: "M-8 1 C -8 -6.5 8 -6.5 8 1 Z", p.trap)
                t.fill(svg: "M-8 3 C -8 10.5 8 10.5 8 3 Z", p.trap)
                t.stroke(svg: "M-7 -2 L-9 -7 M-3.5 -4.5 L-4.5 -10 M0 -5 L0 -11 M3.5 -4.5 L4.5 -10 M7 -2 L9 -7 M-7 6 L-9 10 M0 9 L0 13 M7 6 L9 10", p.leaf, 1.1)
            }
        }
    }

    static func upright(_ d: Drawer, _ p: IllustrationPalette) {
        for (a, s) in [(-48.0, 0.85), (-22, 1), (0, 1.08), (22, 1), (48, 0.85)] as [(CGFloat, CGFloat)] {
            let r = a * .pi / 180, dist = 24 * s
            d.group(50 + sin(r) * dist, 64 - cos(r) * dist, s, a) { l in
                l.fill(Path(ellipseIn: CGRect(x: -8.5, y: -19, width: 17, height: 38)), p.leaf)
                l.stroke(svg: "M0 -17 L0 17", p.leaf2, 1.3)
                for y in [-11, -5, 1, 7, 13] as [CGFloat] {
                    l.stroke(svg: "M-1.5 \(y) L-6 \(y - 3) M1.5 \(y) L6 \(y - 3)", p.leaf2, 2.4)
                }
            }
        }
    }

    static func caudex(_ d: Drawer, _ p: IllustrationPalette, blooming: Bool) {
        d.stroke(svg: "M47 46 L36 26 M50 44 L51 18 M53 46 L66 27", p.trunk, 4.5)
        d.fill(svg: "M38 68 C 30 60 37 47 46 44 L 54 44 C 63 47 70 60 62 68 Z", p.trunk)
        for (i, (x, y)) in ([(36, 26), (51, 18), (66, 27)] as [(CGFloat, CGFloat)]).enumerated() {
            d.ellipse(x - 4.3, y - 3.5, 5, 2.4, rot: -30, p.leaf)
            d.ellipse(x + 4.3, y - 3.5, 5, 2.4, rot: 30, p.leaf)
            if blooming {
                d.flower(x + CGFloat(i - 1) * 3, y - 6, 0.95, CGFloat(i) * 20, petal: p.flower, center: p.flowerCenter)
            }
        }
    }

    static func succulent(_ d: Drawer, _ p: IllustrationPalette) {
        for a in [-78, -52, -26, 0, 26, 52, 78] as [CGFloat] {
            let r = a * .pi / 180
            d.ellipse(50 + sin(r) * 13, 63 - cos(r) * 13, 6, 14, rot: a, p.leaf)
        }
        for a in [-45, -15, 15, 45] as [CGFloat] {
            let r = a * .pi / 180
            d.ellipse(50 + sin(r) * 9, 63 - cos(r) * 9, 4.6, 10, rot: a, p.leafLight)
        }
        d.ellipse(50, 56, 3.5, 7, p.leaf)
    }

    static func sword(_ d: Drawer, _ p: IllustrationPalette) {
        let leaves: [(CGFloat, CGFloat, CGFloat)] = [(38, 40, -9), (62, 42, 9), (44, 52, -3), (56, 50, 4), (50, 58, 0)]
        for (x, h, lean) in leaves {
            let top = 66 - h
            let path = "M\(x - 5) 66 Q \(x - 6) \(66 - h * 0.45) \(x + lean) \(top) Q \(x + 6) \(66 - h * 0.45) \(x + 5) 66 Z"
            d.fill(svg: path, p.leaf)
            var y: CGFloat = 60
            while y > top + 8 {
                let t = (66 - y) / h
                let half = 4.6 * (1 - t * 0.85)
                let cx = x + lean * t * t
                d.stroke(svg: "M\(cx - half * 0.7) \(y) Q \(cx) \(y - 1.6) \(cx + half * 0.7) \(y)", p.leaf2, 1.1)
                y -= 6
            }
            d.stroke(svg: path, p.edge, 1)
        }
    }

    static func tree(_ d: Drawer, _ p: IllustrationPalette) {
        d.stroke(svg: "M50 66 L50 34 M50 50 L39 40 M50 45 L62 35", p.trunk, 3.4)
        let leaves: [(CGFloat, CGFloat, CGFloat, Bool)] = [
            (36, 38, -30, false), (42, 28, -10, true), (50, 22, 0, false), (58, 27, 15, true), (66, 34, 35, false),
            (30, 30, -45, true), (70, 24, 40, false), (38, 20, -20, false), (62, 17, 20, false), (50, 33, 5, true),
            (44, 44, -25, false), (58, 42, 25, false), (25, 40, -60, false), (75, 40, 60, true),
        ]
        for (x, y, r, dark) in leaves {
            d.ellipse(x, y, 4.4, 6.6, rot: r, dark ? p.leaf2 : p.leaf)
        }
    }

    static func fern(_ d: Drawer, _ p: IllustrationPalette) {
        let fronds: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 14, y: 62), CGPoint(x: 26, y: 50)), (CGPoint(x: 86, y: 62), CGPoint(x: 74, y: 50)),
            (CGPoint(x: 18, y: 36), CGPoint(x: 32, y: 40)), (CGPoint(x: 82, y: 36), CGPoint(x: 68, y: 40)),
            (CGPoint(x: 34, y: 16), CGPoint(x: 42, y: 34)), (CGPoint(x: 66, y: 16), CGPoint(x: 58, y: 34)),
            (CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 34)),
        ]
        let base = CGPoint(x: 50, y: 65)
        for (tip, ctrl) in fronds {
            d.stroke(svg: "M\(base.x) \(base.y) Q \(ctrl.x) \(ctrl.y) \(tip.x) \(tip.y)", p.stem, 1.4)
            var t: CGFloat = 0.22
            while t < 0.97 {
                let u = 1 - t
                let pt = CGPoint(x: u * u * base.x + 2 * u * t * ctrl.x + t * t * tip.x,
                                 y: u * u * base.y + 2 * u * t * ctrl.y + t * t * tip.y)
                let tan = CGPoint(x: 2 * u * (ctrl.x - base.x) + 2 * t * (tip.x - ctrl.x),
                                  y: 2 * u * (ctrl.y - base.y) + 2 * t * (tip.y - ctrl.y))
                let ang = atan2(tan.y, tan.x) * 180 / .pi
                let size = 4.4 * (1.05 - t * 0.7)
                for side in [-1.0, 1.0] as [CGFloat] {
                    d.group(pt.x, pt.y, 1, ang + 90 + side * 55) { l in
                        l.fill(Path(ellipseIn: CGRect(x: -1.5, y: -size * 2, width: 3, height: size * 2)), p.leaf)
                    }
                }
                t += 0.085
            }
        }
    }

    static func orchid(_ d: Drawer, _ p: IllustrationPalette, blooming: Bool) {
        d.line(56, 62, 56, 22, p.trunk, 1.3)
        d.stroke(svg: "M52 60 Q 54 32 62 20 Q 70 12 78 18", p.stem, 1.7)
        d.ellipse(38, 61, 13, 4.6, rot: -14, p.leaf)
        d.ellipse(62, 61, 13, 4.6, rot: 14, p.leaf2)
        d.ellipse(50, 59, 11, 4.2, p.leaf)
        if blooming {
            let petal = Color(hex: 0xFFE3EE)
            for (x, y, s) in [(57.0, 30.0, 0.9), (64, 18, 1.05), (76, 18, 1.0)] as [(CGFloat, CGFloat, CGFloat)] {
                d.flower(x, y, s, 0, petal: petal, center: p.flower, rx: 3.4, ry: 4)
                d.circle(x, y + 1.5 * s, 2.2 * s, p.trap)
            }
        } else {
            for (x, y) in [(64.0, 17.0), (76, 18)] as [(CGFloat, CGFloat)] { d.circle(x, y, 1.8, p.leaf) }
        }
    }
}
