import SwiftUI

// MARK: - Brand palette (matches the Candy app icon)

extension Color {
    static let midwayTeal = Color(red: 45 / 255, green: 200 / 255, blue: 180 / 255)
    static let midwayAmber = Color(red: 255 / 255, green: 176 / 255, blue: 32 / 255)
    static let midwayCoral = Color(red: 255 / 255, green: 93 / 255, blue: 115 / 255)
}

// MARK: - Background

/// Soft mesh-gradient wash in the brand palette. Sits behind every screen
/// so the Liquid Glass layers have something colorful to refract.
struct MidwayBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.systemBackground)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.6, 0.4], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
                ],
                colors: [
                    .clear, Color.midwayTeal.opacity(tintStrength), .clear,
                    Color.midwayAmber.opacity(tintStrength), .clear, Color.midwayCoral.opacity(tintStrength),
                    Color.midwayCoral.opacity(tintStrength * 0.6), .clear, Color.midwayTeal.opacity(tintStrength * 0.8),
                ]
            )
        }
        .ignoresSafeArea()
    }

    private var tintStrength: Double {
        colorScheme == .dark ? 0.22 : 0.32
    }
}

// MARK: - Glass helpers

extension View {
    /// A floating Liquid Glass card — the basic building block of the UI.
    func glassCard(cornerRadius: CGFloat = 26, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// Form/list screens: hide the opaque container so the wash shows through.
    func onMidwayBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(MidwayBackground())
    }
}

/// Section label used above groups of glass cards.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }
}
