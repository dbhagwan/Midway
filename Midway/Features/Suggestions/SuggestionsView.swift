import SwiftUI
import MapKit

/// AI-ranked suggestions on a map, with transparent scores per option and
/// per-participant travel times. Picking one creates the meetup card.
struct SuggestionsView: View {
    @EnvironmentObject private var appState: AppState

    let context: PlanningContext
    /// Called after the user confirms a suggestion, so the planner sheet closes.
    var onConfirmed: () -> Void

    @State private var suggestions: [MeetupSuggestion] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedID: UUID?
    @State private var camera: MapCameraPosition = .automatic
    @State private var confirmedMeetup: Meetup?

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(height: 280)

            if isLoading {
                Spacer()
                ProgressView("Balancing travel, interests, and budget…")
                Spacer()
            } else if let errorMessage {
                Spacer()
                ContentUnavailableView("No suggestions",
                                       systemImage: "mappin.slash",
                                       description: Text(errorMessage))
                Spacer()
            } else {
                suggestionList
            }
        }
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSuggestions() }
        .sheet(item: $confirmedMeetup) { meetup in
            MeetupDetailView(meetup: meetup, isNewlyCreated: true) {
                confirmedMeetup = nil
                onConfirmed()
            }
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera) {
            ForEach(context.participants) { participant in
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
                participants: context.participants,
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

    private func loadSuggestions() async {
        guard suggestions.isEmpty else { return }
        do {
            let engine = SuggestionEngineFactory.make()
            suggestions = try await engine.suggestions(for: context)
            selectedID = suggestions.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func confirm(_ suggestion: MeetupSuggestion) {
        let names = context.participants.map(\.name)
        confirmedMeetup = appState.confirm(
            suggestion: suggestion,
            request: context.request,
            attendeeNames: names
        )
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
