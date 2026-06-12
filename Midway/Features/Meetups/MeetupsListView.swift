import SwiftUI

/// Home tab: pending invites, upcoming and past meetups as floating glass
/// cards over the brand wash, plus the entry point to the planner.
struct MeetupsListView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showPlanner: Bool
    @State private var respondingTo: MeetupInvite?
    @State private var votingOn: VotePending?

    private var upcoming: [Meetup] {
        appState.meetups.filter { $0.time >= Date() }.sorted { $0.time < $1.time }
    }

    private var past: [Meetup] {
        appState.meetups.filter { $0.time < Date() }.sorted { $0.time > $1.time }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 14) {
                        if appState.meetups.isEmpty && appState.invites.isEmpty {
                            heroEmptyState
                        } else {
                            content
                        }
                    }
                    .padding()
                }
            }
            .background(MidwayBackground())
            .navigationTitle("Midway")
            .navigationDestination(for: Meetup.self) { meetup in
                MeetupDetailView(meetup: meetup, isNewlyCreated: false, onDone: nil)
            }
            .toolbar {
                Button {
                    showPlanner = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(item: $respondingTo) { invite in
                InviteRespondView(invite: invite)
            }
            .sheet(item: $votingOn) { pending in
                VoteView(pending: pending)
            }
            .refreshable {
                await appState.refresh()
            }
            .task {
                await appState.refresh()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var content: some View {
        if !appState.pendingVoteInvites.isEmpty {
            SectionLabel(text: "Vote on spots")
            ForEach(appState.pendingVoteInvites) { pending in
                Button {
                    votingOn = pending
                } label: {
                    HStack(spacing: 14) {
                        AvatarView(name: pending.organizerName, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(pending.organizerName) found spots")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("\(pending.type.label) · pick your favorite")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Vote")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.midwayTeal)
                    }
                    .glassCard()
                }
                .buttonStyle(.plain)
            }
        }

        if !appState.invites.isEmpty {
            SectionLabel(text: "Invites")
            ForEach(appState.invites) { invite in
                Button {
                    respondingTo = invite
                } label: {
                    InviteCard(invite: invite)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("invite-row")
            }
        }

        if !upcoming.isEmpty {
            SectionLabel(text: "Upcoming")
            ForEach(upcoming) { meetup in
                NavigationLink(value: meetup) {
                    MeetupCard(meetup: meetup)
                }
                .buttonStyle(.plain)
            }
        }

        if !past.isEmpty {
            SectionLabel(text: "Past")
            ForEach(past) { meetup in
                NavigationLink(value: meetup) {
                    MeetupCard(meetup: meetup, isPast: true)
                }
                .buttonStyle(.plain)
            }
        }

        planCTA
            .padding(.top, 6)
    }

    private var heroEmptyState: some View {
        VStack(spacing: 16) {
            AvatarStack(names: ["Ava", "Leo", "Maya", "Sam"], size: 46)
                .padding(.top, 28)
            Text("No meetups yet")
                .font(.title2.bold())
            Text("Start a plan and Midway will find a spot that's fair for everyone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            planCTA
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 32, padding: 24)
        .padding(.top, 40)
    }

    private var planCTA: some View {
        Button {
            showPlanner = true
        } label: {
            Label("Plan a meetup", systemImage: "sparkles")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.glassProminent)
    }
}

// MARK: - Cards

struct InviteCard: View {
    let invite: MeetupInvite

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(name: invite.organizerName, size: 56)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: invite.type.symbolName)
                        .font(.caption2)
                        .padding(5)
                        .background(Color.midwayCoral, in: Circle())
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(invite.type.label) with \(invite.organizerName)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(invite.timeWindow.kind.label) · wants your availability")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Reply")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.midwayCoral)
        }
        .glassCard()
    }
}

struct MeetupCard: View {
    let meetup: Meetup
    var isPast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meetup.title)
                        .font(.headline)
                    Text(meetup.time, format: .dateTime.weekday(.wide).hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(isPast ? .secondary : Color.midwayCoral)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            HStack {
                AvatarStack(names: meetup.attendeeNames, size: 28)
                Text(meetup.attendeeNames.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .glassCard()
        .opacity(isPast ? 0.7 : 1)
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
                    HStack(spacing: 14) {
                        AvatarView(name: invite.organizerName, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(invite.type.label) · \(invite.timeWindow.kind.label)")
                                .font(.headline)
                            Text("\(invite.organizerName) wants to find a fair spot")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
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
            .onMidwayBackground()
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
