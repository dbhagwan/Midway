import SwiftUI

/// Avatar with Snapchat energy: shows the person's real Bitmoji when a URL
/// is available (the user's own from Login Kit; friends' synced through the
/// Midway server from their logins), and otherwise renders a deterministic
/// cartoon face from the person's name — so demo friends still feel like
/// people, not monograms.
struct AvatarView: View {
    let name: String
    var url: URL?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    CartoonAvatar(seed: name, size: size)
                }
            } else {
                CartoonAvatar(seed: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Procedural bitmoji-ish face: pastel disc, skin tone, hair style, eyes,
/// smile, optional blush — all derived stably from a seed string.
struct CartoonAvatar: View {
    let seed: String
    var size: CGFloat = 48

    private struct Look {
        var background: Color
        var skin: Color
        var hair: Color
        var hairStyle: Int   // 0 short, 1 full, 2 buns
        var hasBlush: Bool
    }

    private var look: Look {
        var hash: UInt64 = 5381
        for byte in seed.utf8 { hash = hash &* 33 &+ UInt64(byte) }

        let skins: [Color] = [
            Color(red: 0.99, green: 0.87, blue: 0.74),
            Color(red: 0.94, green: 0.76, blue: 0.60),
            Color(red: 0.80, green: 0.60, blue: 0.45),
            Color(red: 0.62, green: 0.45, blue: 0.34),
            Color(red: 0.45, green: 0.32, blue: 0.24),
        ]
        let hairs: [Color] = [
            Color(red: 0.13, green: 0.12, blue: 0.12),
            Color(red: 0.35, green: 0.22, blue: 0.12),
            Color(red: 0.85, green: 0.64, blue: 0.28),
            Color(red: 0.55, green: 0.28, blue: 0.14),
            Color(red: 0.42, green: 0.42, blue: 0.48),
            Color(red: 0.72, green: 0.32, blue: 0.18),
        ]
        let backgrounds: [Color] = [
            .midwayTeal.opacity(0.45), .midwayAmber.opacity(0.5),
            .midwayCoral.opacity(0.45), Color.purple.opacity(0.35),
            Color.blue.opacity(0.35), Color.mint.opacity(0.45),
        ]
        return Look(
            background: backgrounds[Int(hash % 6)],
            skin: skins[Int((hash >> 8) % 5)],
            hair: hairs[Int((hash >> 16) % 6)],
            hairStyle: Int((hash >> 24) % 3),
            hasBlush: (hash >> 32) % 2 == 0
        )
    }

    var body: some View {
        let look = look
        let face = size * 0.64

        ZStack {
            Circle().fill(look.background)

            ZStack {
                // Face
                Circle().fill(look.skin)

                // Hair: a half-disc over the crown, scaled per style.
                Circle()
                    .trim(from: 0.5, to: 1.0)
                    .fill(look.hair)
                    .scaleEffect(y: look.hairStyle == 1 ? 0.95 : 0.62, anchor: .top)

                if look.hairStyle == 2 {
                    HStack(spacing: face * 0.46) {
                        Circle().fill(look.hair).frame(width: face * 0.26)
                        Circle().fill(look.hair).frame(width: face * 0.26)
                    }
                    .offset(y: -face * 0.46)
                }

                // Eyes
                HStack(spacing: face * 0.22) {
                    Circle().fill(.black.opacity(0.8)).frame(width: face * 0.09)
                    Circle().fill(.black.opacity(0.8)).frame(width: face * 0.09)
                }
                .offset(y: face * 0.06)

                // Blush
                if look.hasBlush {
                    HStack(spacing: face * 0.44) {
                        Circle().fill(Color.midwayCoral.opacity(0.45)).frame(width: face * 0.1)
                        Circle().fill(Color.midwayCoral.opacity(0.45)).frame(width: face * 0.1)
                    }
                    .offset(y: face * 0.2)
                }

                // Smile
                SmileShape()
                    .stroke(.black.opacity(0.75),
                            style: StrokeStyle(lineWidth: max(1.2, face * 0.045), lineCap: .round))
                    .frame(width: face * 0.3, height: face * 0.14)
                    .offset(y: face * 0.27)
            }
            .frame(width: face, height: face)
            .offset(y: size * 0.04)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return path
    }
}

/// Overlapping mini-avatars for attendee groups, Snapchat-story style.
struct AvatarStack: View {
    let names: [String]
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: -size * 0.35) {
            ForEach(Array(names.prefix(4).enumerated()), id: \.offset) { _, name in
                CartoonAvatar(seed: name, size: size)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
            }
            if names.count > 4 {
                Text("+\(names.count - 4)")
                    .font(.caption2.bold())
                    .frame(width: size, height: size)
                    .background(.thinMaterial, in: Circle())
            }
        }
    }
}
