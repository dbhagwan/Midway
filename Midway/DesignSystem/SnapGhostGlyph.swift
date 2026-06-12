import SwiftUI

/// The official Snapchat ghost mark, extracted from Snap's logo (the
/// `SnapGhost` asset is the genuine vector rendered to PNG, background
/// removed). Used on the Login Kit and Creative Kit buttons per Snap's
/// brand guidelines.
struct SnapGhostGlyph: View {
    var size: CGFloat = 20

    var body: some View {
        Image("SnapGhost")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 20) {
        SnapGhostGlyph(size: 22)
        SnapGhostGlyph(size: 44)
        SnapGhostGlyph(size: 88)
    }
    .padding(40)
    .background(Color(red: 1, green: 0.99, blue: 0))
}
