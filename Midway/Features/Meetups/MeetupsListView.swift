import SwiftUI

/// Home tab: upcoming and past meetups, plus the entry point to the planner.
struct MeetupsListView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showPlanner: Bool

    private var upcoming: [Meetup] {
        appState.meetups.filter { $0.time >= Date() }.sorted { $0.time < $1.time }
    }

    private var past: [Meetup] {
        appState.meetups.filter { $0.time < Date() }.sorted { $0.time > $1.time }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.meetups.isEmpty {
                    ContentUnavailableView {
                        Label("No meetups yet", systemImage: "mappin.and.ellipse")
                    } description: {
                        Text("Start a plan and Midway will find a spot that's fair for everyone.")
                    } actions: {
                        Button("Plan a meetup") { showPlanner = true }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    List {
                        if !upcoming.isEmpty {
                            Section("Upcoming") {
                                ForEach(upcoming) { meetup in
                                    NavigationLink(value: meetup) {
                                        MeetupRow(meetup: meetup)
                                    }
                                }
                            }
                        }
                        if !past.isEmpty {
                            Section("Past") {
                                ForEach(past) { meetup in
                                    NavigationLink(value: meetup) {
                                        MeetupRow(meetup: meetup)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Midway")
            .navigationDestination(for: Meetup.self) { meetup in
                MeetupDetailView(meetup: meetup, isNewlyCreated: false, onDone: nil)
            }
            .toolbar {
                Button {
                    showPlanner = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
    }
}

struct MeetupRow: View {
    let meetup: Meetup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meetup.title).font(.headline)
            Text(meetup.time, format: .dateTime.weekday(.wide).hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("With \(meetup.attendeeNames.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
