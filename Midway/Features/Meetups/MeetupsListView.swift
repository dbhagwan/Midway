import SwiftUI

/// Home tab: pending invites, upcoming and past meetups, and the entry
/// point to the planner.
struct MeetupsListView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showPlanner: Bool
    @State private var respondingTo: MeetupInvite?

    private var upcoming: [Meetup] {
        appState.meetups.filter { $0.time >= Date() }.sorted { $0.time < $1.time }
    }

    private var past: [Meetup] {
        appState.meetups.filter { $0.time < Date() }.sorted { $0.time > $1.time }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.meetups.isEmpty && appState.invites.isEmpty {
                    emptyState
                } else {
                    meetupList
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
            .sheet(item: $respondingTo) { invite in
                InviteRespondView(invite: invite)
            }
            .refreshable {
                await appState.refresh()
            }
            .task {
                await appState.refresh()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No meetups yet", systemImage: "mappin.and.ellipse")
        } description: {
            Text("Start a plan and Midway will find a spot that's fair for everyone.")
        } actions: {
            Button("Plan a meetup") { showPlanner = true }
                .buttonStyle(.glassProminent)
        }
    }

    private var meetupList: some View {
        List {
            if !appState.invites.isEmpty {
                Section("Invites") {
                    ForEach(appState.invites) { invite in
                        Button {
                            respondingTo = invite
                        } label: {
                            InviteRow(invite: invite)
                        }
                        .accessibilityIdentifier("invite-row")
                    }
                }
            }

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

            Section {
                Button {
                    showPlanner = true
                } label: {
                    Label("Plan a meetup", systemImage: "plus")
                        .fontWeight(.medium)
                }
            }
        }
    }
}

struct InviteRow: View {
    let invite: MeetupInvite

    var body: some View {
        HStack {
            Image(systemName: invite.type.symbolName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(invite.type.label) with \(invite.organizerName)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(invite.timeWindow.kind.label) · wants your availability")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
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

/// The responder side of the workflow: availability plus per-session
/// location consent — the same choice the organizer makes in the planner.
struct InviteRespondView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let invite: MeetupInvite

    @State private var isAvailable = true
    @State private var sharing: LocationSharingLevel = .approximate
    @State private var manualPlace = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Plan") {
                        Text("\(invite.type.label) · \(invite.timeWindow.kind.label)")
                    }
                    LabeledContent("From") {
                        Text(invite.organizerName)
                    }
                }

                Section("Can you make it?") {
                    Picker("Availability", selection: $isAvailable) {
                        Text("I'm in").tag(true)
                        Text("Can't make it").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                if isAvailable {
                    Section {
                        Picker("Share my location", selection: $sharing) {
                            ForEach(LocationSharingLevel.allCases.filter { $0 != .none }) { level in
                                Text(level.label).tag(level)
                            }
                        }
                        if sharing == .manual {
                            TextField("Where are you? (e.g. Dolores Park)", text: $manualPlace)
                        }
                    } header: {
                        Text("Your location for this plan")
                    } footer: {
                        Text("Used once to balance travel times, then deleted when the plan is confirmed.")
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("You're invited")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    send()
                } label: {
                    HStack {
                        if isSending { ProgressView().tint(.white) }
                        Text("Send response").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .disabled(isSending || (isAvailable && sharing == .manual && manualPlace.isEmpty))
                .padding()
            }
        }
        .onAppear {
            sharing = appState.profile?.defaultLocationSharing == .none
                ? .approximate
                : (appState.profile?.defaultLocationSharing ?? .approximate)
        }
    }

    private func send() {
        isSending = true
        errorMessage = nil
        Task {
            do {
                let response = try await appState.myResponse(
                    sharing: sharing, manualPlace: manualPlace, isAvailable: isAvailable)
                try await appState.respondToInvite(invite, response: response)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
