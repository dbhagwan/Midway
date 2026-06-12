import SwiftUI
import MapKit

/// Drives a planning session to completion: waits for participant
/// responses, runs the suggestion engine over the consented locations, and
/// presents ranked options as a glass carousel floating over a full-bleed
/// map. Confirming a card creates the meetup for everyone.
struct SuggestionsView: View {
    @EnvironmentObject private var appState: AppState

    let session: PlannerSession
    /// Called after the user confirms a suggestion, so the planner sheet closes.
    var onConfirmed: () -> Void

    private enum Phase: Equatable {
        case waiting(awaiting: [String])
        case ranking
        case ready
        case failed(String)
    }

    @State private var phase: Phase = .waiting(awaiting: [])
    @State private var participants: [PlanningParticipant] = []
    @State private var suggestions: [MeetupSuggestion] = []
    @State private var votersByRank: [Int: [String]] = [:]
    @State private var selectedIndex = 0
    @State private var camera: MapCameraPosition = .automatic
    @State private var confirmedMeetup: Meetup?

    private var selectedID: UUID? {
        suggestions.indices.contains(selectedIndex) ? suggestions[selectedIndex].id : nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            map.ignoresSafeArea(edges: .bottom)

            switch phase {
            case .waiting(let awaiting):
                statusPanel {
                    ProgressView()
                    Text(awaiting.isEmpty
                         ? "Collecting responses…"
                         : "Waiting for \(awaiting.joined(separator: ", "))…")
                        .font(.headline)
                    Text("Friends choose their own availability and location sharing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            case .ranking:
                statusPanel {
                    ProgressView()
                    Text("Balancing travel, interests, and budget…")
                        .font(.headline)
                }
            case .failed(let message):
                statusPanel {
                    Image(systemName: "mappin.slash")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
            case .ready:
                carousel
            }
        }
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await run() }
        .sheet(item: $confirmedMeetup) { meetup in
            MeetupDetailView(meetup: meetup, isNewlyCreated: true) {
                confirmedMeetup = nil
                onConfirmed()
            }
        }
    }

    // MARK: - Session loop

    private func run() async {
        guard suggestions.isEmpty else { return }
        let deadline = Date().addingTimeInterval(120)

        // Poll until everyone has answered (or rank with whoever responded).
        var state: MeetupSessionState?
        while Date() < deadline {
            do {
                let current = try await appState.backend.sessionState(session.id)
                state = current
                participants = current.participants  // pins appear as friends reply
                if current.status == .ready { break }
                phase = .waiting(awaiting: current.awaitingNames)
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }

        guard let state, state.participants.count >= 2 else {
            phase = .failed("Nobody shared availability in time. Try again, or pick different friends.")
            return
        }

        participants = state.participants
        phase = .ranking
        do {
            let context = PlanningContext(request: session.request,
                                          participants: state.participants)
            let engine = SuggestionEngineFactory.make()
            suggestions = try await engine.suggestions(for: context)
            selectedIndex = 0
            phase = .ready
            focus(on: 0, animated: false)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        // Publish the ranked options so the group can vote, then keep the
        // tallies live while this screen is up. Only write state on actual
        // changes — constant invalidation makes the UI churn (and starves
        // XCUITest's accessibility snapshots on CI).
        try? await appState.backend.publishSuggestions(sessionID: session.id, suggestions)
        while !Task.isCancelled, phase == .ready {
            if let options = try? await appState.backend.votableSuggestions(sessionID: session.id) {
                let tallies = Dictionary(uniqueKeysWithValues: options.map {
                    ($0.rank, $0.voterNames)
                })
                if tallies != votersByRank {
                    votersByRank = tallies
                }
            }
            // Demo votes land once and never change; stop polling there.
            if TestEnvironment.isUITest, !votersByRank.isEmpty { break }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera) {
            ForEach(participants) { participant in
                Annotation(participant.name, coordinate: participant.coordinate.clCoordinate) {
                    CartoonAvatar(seed: participant.name, size: 30)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(radius: 2)
                }
            }
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Marker("\(index + 1). \(suggestion.venueName)",
                       coordinate: suggestion.coordinate.clCoordinate)
                    .tint(suggestion.id == selectedID ? Color.midwayCoral : Color.secondary)
            }
        }
    }

    private func focus(on index: Int, animated: Bool = true) {
        guard suggestions.indices.contains(index) else { return }
        let region = MKCoordinateRegion(
            center: suggestions[index].coordinate.clCoordinate,
            latitudinalMeters: 1800, longitudinalMeters: 1800)
        if animated {
            withAnimation(.snappy) { camera = .region(region) }
        } else {
            camera = .region(region)
        }
    }

    // MARK: - Overlays

    private func statusPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 28, padding: 24)
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    private var carousel: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                SuggestionCard(
                    rank: index + 1,
                    suggestion: suggestion,
                    participants: participants,
                    voters: votersByRank[index + 1] ?? []
                ) {
                    confirm(suggestion)
                }
                .padding(.horizontal, 20)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 330)
        .padding(.bottom, 8)
        .onChange(of: selectedIndex) { _, newIndex in
            focus(on: newIndex)
        }
    }

    // MARK: - Actions

    private func confirm(_ suggestion: MeetupSuggestion) {
        Task {
            do {
                confirmedMeetup = try await appState.confirm(
                    suggestion: suggestion,
                    session: session,
                    attendeeNames: participants.map(\.name))
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Card

struct SuggestionCard: View {
    let rank: Int
    let suggestion: MeetupSuggestion
    let participants: [PlanningParticipant]
    var voters: [String] = []
    var onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(rank)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.midwayCoral, in: Circle())
                VStack(alignment: .leading) {
                    Text(suggestion.venueName)
                        .font(.title3.bold())
                        .lineLimit(1)
                    Text("\(suggestion.category)\(suggestion.areaName.isEmpty ? "" : " · \(suggestion.areaName)")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(suggestion.suggestedTime, style: .time)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.midwayCoral)
            }

            // Transparent scoring — the "why", not just the "what".
            HStack(spacing: 10) {
                ScorePill(label: "Fair", value: suggestion.fairnessScore, symbol: "scalemass")
                ScorePill(label: "Interests", value: suggestion.interestScore, symbol: "heart")
                ScorePill(label: "Budget", value: suggestion.budgetFitScore, symbol: "dollarsign.circle")
            }

            // Per-person travel times, with faces.
            HStack(spacing: 14) {
                ForEach(participants) { participant in
                    if let minutes = suggestion.travelMinutesByParticipant[participant.id] {
                        HStack(spacing: 5) {
                            CartoonAvatar(seed: participant.name, size: 20)
                            Label("\(Int(minutes.rounded()))m",
                                  systemImage: participant.transportMode.symbolName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text(suggestion.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !voters.isEmpty {
                HStack(spacing: 6) {
                    AvatarStack(names: voters, size: 20)
                    Text(voters.count == 1
                         ? "\(voters[0]) voted for this"
                         : "\(voters.count) votes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.midwayTeal)
                }
            }

            Button(action: onPick) {
                Text("Meet here")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
        }
        .glassCard(cornerRadius: 30, padding: 18)
    }
}

struct ScorePill: View {
    let label: String
    let value: Double
    let symbol: String

    var body: some View {
        Label("\(label) \(Int((value * 100).rounded()))", systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .glassEffect(.regular.tint(tint.opacity(0.25)), in: .capsule)
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch value {
        case 0.7...: return Color(red: 0.1, green: 0.6, blue: 0.35)
        case 0.4..<0.7: return .orange
        default: return Color.midwayCoral
        }
    }
}
