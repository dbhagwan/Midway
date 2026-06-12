import SwiftUI

/// The Candy app icon brought to life: the meridian line draws in, the two
/// friend dots spring on at the ends, and the coral midpoint pops — then
/// keeps breathing with a soft ripple. Used as the opening panel.
struct AnimatedMeridianLogo: View {
    var size: CGFloat = 200

    @State private var lineProgress: CGFloat = 0
    @State private var endDotsShown = false
    @State private var midShown = false
    @State private var ripple = false
    @State private var breathe = false

    var body: some View {
        let lineLength = size * 0.60
        let endRadius = size * 0.047
        let midRadius = size * 0.064

        ZStack {
            // The meridian line, drawing outward from the center.
            Capsule()
                .fill(.primary.opacity(0.72))
                .frame(width: max(lineLength * lineProgress, 0.5), height: size * 0.014)

            // Ripple radiating from the midpoint once everyone has "met".
            Circle()
                .stroke(Color.midwayCoral.opacity(ripple ? 0 : 0.45),
                        lineWidth: size * 0.012)
                .frame(width: midRadius * 2, height: midRadius * 2)
                .scaleEffect(ripple ? 3.4 : 1)
                .opacity(midShown ? 1 : 0)

            // Friend dots arriving at each end.
            Circle()
                .fill(Color.midwayTeal)
                .frame(width: endRadius * 2, height: endRadius * 2)
                .scaleEffect(endDotsShown ? 1 : 0.001)
                .offset(x: -lineLength / 2)
            Circle()
                .fill(Color.midwayAmber)
                .frame(width: endRadius * 2, height: endRadius * 2)
                .scaleEffect(endDotsShown ? 1 : 0.001)
                .offset(x: lineLength / 2)

            // The midpoint — where they meet — breathing gently.
            Circle()
                .fill(Color.midwayCoral)
                .frame(width: midRadius * 2, height: midRadius * 2)
                .scaleEffect(midShown ? (breathe ? 1.09 : 1.0) : 0.001)
                .shadow(color: .midwayCoral.opacity(breathe ? 0.45 : 0.15),
                        radius: size * 0.05)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).delay(0.2)) {
                lineProgress = 1
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.6)) {
                endDotsShown = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5).delay(1.05)) {
                midShown = true
            }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(1.6)) {
                ripple = true
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true).delay(1.6)) {
                breathe = true
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        MidwayBackground()
        AnimatedMeridianLogo(size: 220)
            .glassEffect(.regular, in: .rect(cornerRadius: 49))
    }
}
