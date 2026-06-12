import SwiftUI

/// Branded card rendered to an image for sharing (Snapchat, Messages, …).
/// Solid colors only — glass effects need a live backdrop and won't render
/// through ImageRenderer.
struct MeetupShareCard: View {
    let meetup: Meetup

    var body: some View {
        VStack(spacing: 18) {
            // Static meridian mark
            ZStack {
                Capsule()
                    .fill(.black.opacity(0.65))
                    .frame(width: 110, height: 3)
                HStack {
                    Circle().fill(Color.midwayTeal).frame(width: 16)
                    Spacer()
                    Circle().fill(Color.midwayAmber).frame(width: 16)
                }
                .frame(width: 126)
                Circle().fill(Color.midwayCoral).frame(width: 22)
            }
            .padding(.top, 26)

            VStack(spacing: 6) {
                Text(meetup.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text("\(meetup.venueName)\(meetup.areaName.isEmpty ? "" : " · \(meetup.areaName)")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(meetup.time, format: .dateTime.weekday(.wide).month().day().hour().minute())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.midwayCoral)
            }
            .padding(.horizontal, 24)

            AvatarStack(names: meetup.attendeeNames, size: 36)

            Text("planned with Midway")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 22)
        }
        .frame(width: 340)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.97, blue: 0.92),
                    Color.midwayTeal.opacity(0.18),
                    Color.midwayCoral.opacity(0.16),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}
