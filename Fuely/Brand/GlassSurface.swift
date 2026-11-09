import SwiftUI

/// A soft, rounded surface: Liquid Glass on iOS 26+, a system material on iOS 18–25
/// (DECISIONS P2: same colors and layout everywhere).
struct FuelyGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = FuelySpacing.cardRadius
    /// Optional brand tint, kept very light so text stays legible.
    var tint: Color?
    var padding: CGFloat? = FuelySpacing.m

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let padded = content.padding(padding ?? 0)
        if #available(iOS 26, *) {
            padded.glassEffect(.regular.tint(tint?.opacity(0.10)), in: shape)
        } else {
            padded
                .background {
                    shape.fill(.regularMaterial)
                        .overlay { if let tint { shape.fill(tint.opacity(0.06)) } }
                }
                .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
        }
    }
}

extension View {
    /// Wraps the view in a Fuely card (glass on iOS 26+, material before).
    func fuelyCard(tint: Color? = nil, cornerRadius: CGFloat = FuelySpacing.cardRadius,
                   padding: CGFloat? = FuelySpacing.m) -> some View {
        modifier(FuelyGlassSurface(cornerRadius: cornerRadius, tint: tint, padding: padding))
    }

    /// Prominent call-to-action: `.glassProminent` on iOS 26+, `.borderedProminent` before.
    @ViewBuilder
    func fuelyProminentButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Secondary button: `.glass` on iOS 26+, `.bordered` before.
    @ViewBuilder
    func fuelySecondaryButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

#Preview("Card styles") {
    VStack(spacing: FuelySpacing.m) {
        Text("Plain card").frame(maxWidth: .infinity, alignment: .leading).fuelyCard()
        Text("Water tint").frame(maxWidth: .infinity, alignment: .leading).fuelyCard(tint: FuelyColor.water)
        Button("Log water") {}.fuelyProminentButton()
        Button("Custom") {}.fuelySecondaryButton()
    }
    .padding()
    .frame(maxHeight: .infinity)
    .fuelyScreenBackground()
}
