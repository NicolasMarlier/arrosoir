import SwiftUI

// MARK: - Couleurs « Papiers découpés »

extension Color {
    nonisolated init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static let cream = Color(hex: 0xFFF4E2)
    static let ink = Color(hex: 0x1C1B3A)
    static let muted = Color(hex: 0x7A7488)
    static let vermillon = Color(hex: 0xFF5A36)
    static let mustard = Color(hex: 0xFFB627)
    static let cobalt = Color(hex: 0x2B59C3)
    static let leafGreen = Color(hex: 0x1F8A4C)
    static let leafDark = Color(hex: 0x0F5E33)
    static let pinkFlower = Color(hex: 0xFF7EB6)
    static let sage = Color(hex: 0xC9E6C4)
    static let sand = Color(hex: 0xFFD88A)
    static let blush = Color(hex: 0xFFC4DC)
    static let sky = Color(hex: 0xC8D8FF)
    static let paper = Color(hex: 0xFFFAF2)
    static let dashed = Color(hex: 0xEAD9BD)
}

// MARK: - Typo Bricolage Grotesque

enum BricoWeight: String {
    case regular = "BricolageGrotesque-Regular"
    case semibold = "BricolageGrotesque-SemiBold"
    case bold = "BricolageGrotesque-Bold"
    case heavy = "BricolageGrotesque-ExtraBold"
}

extension Font {
    static func brico(_ size: CGFloat, _ weight: BricoWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }
}

// MARK: - Couleurs de pot (une par plante, attribuée automatiquement)

nonisolated struct PotStyle: Sendable, Equatable {
    let pot: UInt32
    let rim: UInt32
    let lightFace: Bool
    let tint: UInt32

    static let all: [PotStyle] = [
        PotStyle(pot: 0xFF5A36, rim: 0x2B59C3, lightFace: true, tint: 0xC9E6C4),
        PotStyle(pot: 0x2B59C3, rim: 0xFF5A36, lightFace: true, tint: 0xFFD88A),
        PotStyle(pot: 0xFFB627, rim: 0xFF5A36, lightFace: false, tint: 0xFFC4DC),
        PotStyle(pot: 0xFF7EB6, rim: 0x2B59C3, lightFace: false, tint: 0xFFD88A),
        PotStyle(pot: 0xFF5A36, rim: 0xFFB627, lightFace: true, tint: 0xC8D8FF),
        PotStyle(pot: 0x2B59C3, rim: 0xFFB627, lightFace: true, tint: 0xFFC4DC),
        PotStyle(pot: 0xFFB627, rim: 0x2B59C3, lightFace: false, tint: 0xC8D8FF),
        PotStyle(pot: 0xFF7EB6, rim: 0xFF5A36, lightFace: false, tint: 0xC9E6C4),
    ]

    static func at(_ index: Int) -> PotStyle { all[((index % all.count) + all.count) % all.count] }

    var tintColor: Color { Color(hex: tint) }
}

// MARK: - Composants

struct CardBackground: ViewModifier {
    var color: Color = .white
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

extension View {
    /// Largeur de lecture confortable, centrée (iPad).
    func readable(_ maxWidth: CGFloat = 720) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }

    func card(_ color: Color = .white) -> some View { modifier(CardBackground(color: color)) }
}

struct PillButtonStyle: ButtonStyle {
    enum Kind { case fill, outline, dark, light }
    var kind: Kind = .fill
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.brico(compact ? 12 : 14, .heavy))
            .padding(.vertical, compact ? 6 : 11)
            .padding(.horizontal, compact ? 14 : 16)
            .frame(maxWidth: compact ? nil : .infinity)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay {
                if kind == .outline { Capsule().strokeBorder(Color.ink, lineWidth: 2) }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .fill, .dark: .white
        case .outline, .light: .ink
        }
    }

    private var background: Color {
        switch kind {
        case .fill: .vermillon
        case .dark: .ink
        case .outline: .clear
        case .light: .white
        }
    }
}

struct Sticker: View {
    let text: String
    var color: Color = .mustard
    var body: some View {
        Text(text)
            .font(.brico(14, .heavy))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .rotationEffect(.degrees(-2.5))
    }
}

struct Tag: View {
    let text: String
    var background: Color = .cobalt
    var foreground: Color = .white
    var body: some View {
        Text(text)
            .font(.brico(11, .heavy))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.brico(11, .heavy))
            .tracking(1.3)
            .foregroundStyle(Color.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var mutedValue = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(Color.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.brico(14, mutedValue ? .regular : .bold))
                .foregroundStyle(mutedValue ? Color.muted : Color.ink)
                .multilineTextAlignment(.trailing)
        }
        .font(.brico(14))
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Line().stroke(Color.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(height: 1)
        }
    }
}

nonisolated struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// Forme organique type « papier découpé » pour les fonds.
nonisolated struct Blob: Shape {
    var seed: Int = 0
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let j: [CGFloat] = [0.06, -0.04, 0.05, -0.06, 0.03, -0.05, 0.04, -0.03]
        func o(_ i: Int) -> CGFloat { j[(i + seed) % j.count] }
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: h * (0.0 + o(0))))
        p.addCurve(to: CGPoint(x: w * (1 + o(1)), y: h * 0.5),
                   control1: CGPoint(x: w * 0.85, y: h * (0.0 + o(2))),
                   control2: CGPoint(x: w * (1 + o(3)), y: h * 0.2))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h * (1 + o(4))),
                   control1: CGPoint(x: w * (1 + o(5)), y: h * 0.85),
                   control2: CGPoint(x: w * 0.8, y: h * (1 + o(6))))
        p.addCurve(to: CGPoint(x: w * (0 + o(7)), y: h * 0.5),
                   control1: CGPoint(x: w * 0.2, y: h * (1 + o(1))),
                   control2: CGPoint(x: w * (0 + o(3)), y: h * 0.85))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h * (0.0 + o(0))),
                   control1: CGPoint(x: w * (0 + o(5)), y: h * 0.15),
                   control2: CGPoint(x: w * 0.15, y: h * (0.0 + o(6))))
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
