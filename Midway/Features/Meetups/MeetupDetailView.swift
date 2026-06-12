import SwiftUI
import MapKit
import EventKit
#if canImport(SCSDKCreativeKit)
import SCSDKCreativeKit
#endif

/// The confirmed meetup card: where, when, who — with calendar add and
/// Apple Maps handoff for directions.
struct MeetupDetailView: View {
    @EnvironmentObject private var appState: AppState

    let meetup: Meetup
    let isNewlyCreated: Bool
    var onDone: (() -> Void)?

    @State private var calendarStatus: String?
    @State private var onMyWaySent = false
    @State private var shareImage: UIImage?

    var body: some View {
        if isNewlyCreated {
            // Presented as its own sheet, so it needs its own stack — and the
            // title must be applied inside the stack to reach its nav bar.
            NavigationStack {
                card
                    .navigationTitle("It's a plan!")
                    .navigationBarTitleDisplayMode(.inline)
            }
        } else {
            card
                .navigationTitle("Meetup")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var card: some View {
        List {
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: meetup.coordinate.clCoordinate,
                    latitudinalMeters: 1200, longitudinalMeters: 1200))
                ) {
                    Marker(meetup.venueName, coordinate: meetup.coordinate.clCoordinate)
                }
                .frame(height: 180)
                .listRowInsets(EdgeInsets())
            }

            Section {
                LabeledContent("Where") {
                    Text("\(meetup.venueName)\(meetup.areaName.isEmpty ? "" : ", \(meetup.areaName)")")
                }
                LabeledContent("When") {
                    Text(meetup.time, format: .dateTime.weekday(.wide).month().day().hour().minute())
                }
                HStack {
                    Text("Who")
                    Spacer()
                    AvatarStack(names: meetup.attendeeNames, size: 28)
                    Text(meetup.attendeeNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Section("Why this spot") {
                Text(meetup.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    openInMaps()
                } label: {
                    Label("Directions in Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                Button {
                    addToCalendar()
                } label: {
                    Label(calendarStatus ?? "Add to Calendar", systemImage: "calendar.badge.plus")
                }
                .disabled(calendarStatus != nil)
                if meetup.time > Date() {
                    Button {
                        sendOnMyWay()
                    } label: {
                        Label(onMyWaySent ? "Told everyone you're coming" : "I'm on my way",
                              systemImage: "figure.walk.motion")
                    }
                    .disabled(onMyWaySent)
                }
            }

            Section("Share the plan") {
                if let shareImage {
                    ShareLink(
                        item: Image(uiImage: shareImage),
                        preview: SharePreview(meetup.title, image: Image(uiImage: shareImage))
                    ) {
                        Label("Share meetup card", systemImage: "square.and.arrow.up")
                    }
                }
                if canShareToSnapchat {
                    Button {
                        shareToSnapchat()
                    } label: {
                        HStack(spacing: 10) {
                            SnapGhostGlyph(size: 20)
                            Text("Send as a Snap")
                        }
                    }
                }
            }

            if !isNewlyCreated {
                Section {
                    Button(role: .destructive) {
                        appState.delete(meetup: meetup)
                    } label: {
                        Label("Delete meetup", systemImage: "trash")
                    }
                }
            }
        }
        .onMidwayBackground()
        .onAppear {
            if shareImage == nil {
                let renderer = ImageRenderer(content: MeetupShareCard(meetup: meetup))
                renderer.scale = 3
                shareImage = renderer.uiImage
            }
        }
        .toolbar {
            if isNewlyCreated {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone?() }
                }
            }
        }
    }

    // MARK: - Actions

    private func sendOnMyWay() {
        onMyWaySent = true
        Task { await appState.backend.sendOnMyWay(meetupID: meetup.id) }
    }

    private var canShareToSnapchat: Bool {
        #if canImport(SCSDKCreativeKit)
        return SnapchatAuthService().isAvailable && shareImage != nil
        #else
        return false
        #endif
    }

    private func shareToSnapchat() {
        #if canImport(SCSDKCreativeKit)
        guard let shareImage else { return }
        let photo = SCSDKSnapPhoto(image: shareImage)
        let content = SCSDKPhotoSnapContent(snapPhoto: photo)
        content.caption = "Meet me midway 📍"
        SCSDKSnapAPI().startSending(content)
        #endif
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: meetup.coordinate.clCoordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = meetup.venueName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault,
        ])
    }

    private func addToCalendar() {
        let store = EKEventStore()
        store.requestWriteOnlyAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                guard granted else {
                    calendarStatus = "Calendar access denied"
                    return
                }
                let event = EKEvent(eventStore: store)
                event.title = meetup.title
                event.location = "\(meetup.venueName), \(meetup.areaName)"
                event.startDate = meetup.time
                event.endDate = meetup.time.addingTimeInterval(90 * 60)
                event.notes = meetup.explanation
                event.calendar = store.defaultCalendarForNewEvents
                // A nudge shortly before it's time to leave.
                event.addAlarm(EKAlarm(relativeOffset: -45 * 60))
                do {
                    try store.save(event, span: .thisEvent)
                    calendarStatus = "Added to Calendar"
                } catch {
                    calendarStatus = "Couldn't add to Calendar"
                }
            }
        }
    }
}
