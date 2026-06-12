import SwiftUI
import MapKit

/// The participant side of group voting: the organizer published ranked
/// options; pick a favorite (revotable until the plan is confirmed).
struct VoteView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let pending: VotePending

    @State private var options: [VotableSuggestion] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading options…")
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't load options",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else {
                    ScrollView {
                        GlassEffectContainer(spacing: 14) {
                            VStack(spacing: 14) {
                                Text("\(pending.organizerName) found \(options.count) fair spots for \(pending.type.label.lowercased()) — which works for you?")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                ForEach(options) { option in
                                    optionCard(option)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .background(MidwayBackground())
            .navigationTitle("Vote on spots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func optionCard(_ option: VotableSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(option.rank)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.midwayCoral, in: Circle())
                VStack(alignment: .leading) {
                    Text(option.venueName).font(.headline)
                    Text("\(option.category)\(option.areaName.isEmpty ? "" : " · \(option.areaName)")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(option.time, style: .time)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.midwayCoral)
            }

            HStack(spacing: 10) {
                ScorePill(label: "Fair", value: option.fairnessScore, symbol: "scalemass")
                ScorePill(label: "Interests", value: option.interestScore, symbol: "heart")
                ScorePill(label: "Budget", value: option.budgetFitScore, symbol: "dollarsign.circle")
            }

            Text(option.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
                if !option.voterNames.isEmpty {
                    AvatarStack(names: option.voterNames, size: 20)
                    Text("\(option.voterNames.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    vote(for: option)
                } label: {
                    Label(option.myVote ? "Your pick" : "Vote",
                          systemImage: option.myVote ? "checkmark" : "hand.thumbsup")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glassProminent)
                .tint(option.myVote ? .midwayTeal : .midwayCoral)
                .controlSize(.small)
            }
        }
        .glassCard()
    }

    private func load() async {
        do {
            options = try await appState.backend.votableSuggestions(sessionID: pending.id)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func vote(for option: VotableSuggestion) {
        Task {
            try? await appState.backend.castVote(sessionID: pending.id, suggestionID: option.id)
            await load()
            await appState.refresh()
        }
    }
}
