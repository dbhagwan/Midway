import SwiftUI

/// The planning wizard: who, what, when, constraints, and the organizer's
/// location consent for this session. Designed to take under a minute for a
/// simple two-person meetup.
struct NewMeetupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var meetupType: MeetupType = .coffee
    @State private var timeKind: TimeWindowKind = .now
    @State private var customStart = Date().addingTimeInterval(3600)

    @State private var maxBudget: BudgetRange?
    @State private var indoorOutdoor: MeetupConstraints.IndoorOutdoor = .either
    @State private var dietary = ""
    @State private var vibe = ""
    @State private var travelCapEnabled = false
    @State private var travelCap = 30

    @State private var sharing: LocationSharingLevel = .approximate
    @State private var manualPlace = ""

    @State private var plannerSession: PlannerSession?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                friendsSection
                detailsSection
                constraintsSection
                locationSection

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .onMidwayBackground()
            .navigationTitle("New meetup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    generate()
                } label: {
                    HStack {
                        if isGenerating { ProgressView().tint(.white) }
                        Text(isGenerating ? "Asking your friends…" : "Find places")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .disabled(selectedFriendIDs.isEmpty || isGenerating
                          || (sharing == .manual && manualPlace.isEmpty))
                .padding()
            }
            .navigationDestination(item: $plannerSession) { session in
                SuggestionsView(session: session) {
                    dismiss()
                }
            }
        }
        .onAppear {
            sharing = appState.profile?.defaultLocationSharing ?? .approximate
            if let favorite = appState.profile?.favoriteMeetupTypes.first {
                meetupType = favorite
            }
        }
    }

    // MARK: - Sections

    private var friendsSection: some View {
        Section("Who's coming?") {
            if appState.acceptedFriends.isEmpty {
                Text("Add friends first — Midway shows only friends who are on Midway.")
                    .foregroundStyle(.secondary)
            }
            ForEach(appState.acceptedFriends) { friend in
                Button {
                    toggle(friend.id)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(name: friend.displayName, url: friend.avatarURL, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayName)
                                .foregroundStyle(.primary)
                            if !friend.homeAreaName.isEmpty {
                                Text(friend.homeAreaName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: selectedFriendIDs.contains(friend.id)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedFriendIDs.contains(friend.id)
                                             ? Color.midwayCoral : Color.secondary)
                    }
                }
            }
        }
    }

    private var detailsSection: some View {
        Section("What and when") {
            Picker("Type", selection: $meetupType) {
                ForEach(MeetupType.allCases) { type in
                    Label(type.label, systemImage: type.symbolName).tag(type)
                }
            }
            Picker("When", selection: $timeKind) {
                ForEach(TimeWindowKind.allCases) { Text($0.label).tag($0) }
            }
            if timeKind == .custom {
                DatePicker("Starting", selection: $customStart, in: Date()...)
            }
        }
    }

    private var constraintsSection: some View {
        Section("Constraints (optional)") {
            Picker("Max budget", selection: $maxBudget) {
                Text("Anyone's default").tag(BudgetRange?.none)
                ForEach(BudgetRange.allCases) { Text($0.label).tag(BudgetRange?.some($0)) }
            }
            Picker("Setting", selection: $indoorOutdoor) {
                ForEach(MeetupConstraints.IndoorOutdoor.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("Dietary needs (e.g. vegetarian)", text: $dietary)
            TextField("Vibe (e.g. lowkey, good for talking)", text: $vibe)
            Toggle("Cap travel time", isOn: $travelCapEnabled)
            if travelCapEnabled {
                Stepper("Max \(travelCap) min each way", value: $travelCap, in: 10...90, step: 5)
            }
        }
    }

    private var locationSection: some View {
        Section {
            Picker("Share my location", selection: $sharing) {
                ForEach(LocationSharingLevel.allCases) { Text($0.label).tag($0) }
            }
            if sharing == .manual {
                TextField("Where are you? (e.g. Dolores Park)", text: $manualPlace)
            }
            if sharing == .none {
                Text("Midway will use your home neighborhood instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Your location for this plan")
        } footer: {
            Text("Shared once, for this plan only. Friends choose their own sharing level when they respond.")
        }
    }

    // MARK: - Actions

    private func toggle(_ id: UUID) {
        if selectedFriendIDs.contains(id) {
            selectedFriendIDs.remove(id)
        } else {
            selectedFriendIDs.insert(id)
        }
    }

    private func generate() {
        guard let profile = appState.profile else { return }
        isGenerating = true
        errorMessage = nil

        var window = TimeWindow(kind: timeKind)
        if timeKind == .custom {
            window.customStart = customStart
        }
        let request = MeetupRequest(
            organizerID: profile.id,
            participantFriendIDs: Array(selectedFriendIDs),
            type: meetupType,
            timeWindow: window,
            constraints: MeetupConstraints(
                maxBudget: maxBudget,
                indoorOutdoor: indoorOutdoor,
                dietaryNeeds: dietary.isEmpty
                    ? []
                    : dietary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                vibe: vibe,
                maxTravelMinutes: travelCapEnabled ? travelCap : nil
            )
        )

        Task {
            do {
                let organizerResponse = try await appState.myResponse(
                    sharing: sharing, manualPlace: manualPlace)
                plannerSession = try await appState.startMeetup(
                    request, organizerResponse: organizerResponse)
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}

#Preview {
    NewMeetupView().environmentObject(AppState())
}
