import SwiftUI
import MapKit
import EventKit

/// The confirmed meetup card: where, when, who — with calendar add and
/// Apple Maps handoff for directions.
struct MeetupDetailView: View {
    @EnvironmentObject private var appState: AppState

    let meetup: Meetup
    let isNewlyCreated: Bool
    var onDone: (() -> Void)?

    @State private var calendarStatus: String?

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
                LabeledContent("Who") {
                    Text(meetup.attendeeNames.joined(separator: ", "))
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
        .toolbar {
            if isNewlyCreated {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone?() }
                }
            }
        }
    }

    // MARK: - Actions

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
