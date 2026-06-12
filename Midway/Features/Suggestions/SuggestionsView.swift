import SwiftUI
import MapKit

/// Drives a planning session to completion: waits for participant
/// responses, runs the suggestion engine over the consented locations,
/// shows ranked options on a map, and confirms the group's pick.
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
    @State private var selectedID: UUID?
    @State private var camera: MapCameraPosition = .automatic
    @State private var confirmedMeetup: Meetup?

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(height: 280)

            switch phase {
            case .waiting(let awaiting):
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(awaiting.isEmpty
                         ? "Collecting responses…"
                         : "Waiting for \(awaiting.joined(separator: ", "))…")
                        .foregroundStyle(.secondary)
                    Text("Friends choose their own availability and location sharing.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                Spacer()
            case .ranking:
                Spacer()
                ProgressView("Balancing travel, interests, and budget…")
                Spacer()
            case .failed(let message):
                Spacer()
                ContentUnavailableView("No suggestions",
                                       systemImage: "mappin.slash",
                                       description: Text(message))
                Spacer()
            case .ready:
                suggestionList
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

        // Poll until everyone has answered (or we run out of patience and
        // rank with whoever responded).
        var state: MeetupSessionState?
        while Date() < deadline {
            do {
                let current = try await appState.backend.sessionState(session.id)
                state = current
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
            selectedID = suggestions.first?.id
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera) {
            ForEach(participants) { participant in
                Annotation(participant.name, coordinate: participant.coordinate.clCoordinate) {
                    Image(systemName: "person.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .blue)
                }
            }
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Marker("\(index + 1). \(suggestion.venueName)",
                       coordinate: suggestion.coordinate.clCoordinate)
                    .tint(suggestion.id == selectedID ? .orange : .red)
            }
        }
    }

    // MARK: - List

    private var suggestionList: some View {
        List(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
            SuggestionCard(
                rank: index + 1,
                suggestion: suggestion,
                participants: participants,
                isSelected: suggestion.id == selectedID
            ) {
                confirm(suggestion)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedID = suggestion.id
                withAnimation {
                    camera = .region(MKCoordinateRegion(
                        center: suggestion.coordinate.clCoordinate,
                        latitudinalMeters: 1500, longitudinalMeters: 1500))
                }
            }
        }
        .listStyle(.plain)
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
    let isSelected: Bool
    var onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(rank)")
                    .font(.headline)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                VStack(alignment: .leading) {
                    Text(suggestion.venueName).font(.headline)
                    Text("\(suggestion.category)\(suggestion.areaName.isEmpty ? "" : " · \(suggestion.areaName)")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(suggestion.suggestedTime, style: .time)
                    .font(.subheadline.weight(.medium))
            }

            // Transparent scoring — the "why", not just the "what".
            HStack(spacing: 12) {
                ScorePill(label: "Fair", value: suggestion.fairnessScore, symbol: "scalemass")
                ScorePill(label: "Interests", value: suggestion.interestScore, symbol: "heart")
                ScorePill(label: "Budget", value: suggestion.budgetFitScore, symbol: "dollarsign.circle")
            }

            // Per-person travel times.
            HStack(spacing: 14) {
                ForEach(participants) { participant in
                    if let minutes = suggestion.travelMinutesByParticipant[participant.id] {
                        Label("\(participant.name) \(Int(minutes.rounded()))m",
                              systemImage: participant.transportMode.symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(suggestion.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: onPick) {
                Text("Meet here")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.08) : nil)
    }
}

struct ScorePill: View {
    let label: String
    let value: Double
    let symbol: String

    var body: some View {
        Label("\(label) \(Int((value * 100).rounded()))", systemImage: symbol)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch value {
        case 0.7...: return .green
        case 0.4..<0.7: return .orange
        default: return .red
        }
    }
}
