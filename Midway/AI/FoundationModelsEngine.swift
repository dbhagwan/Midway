#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Suggestion engine backed by Apple's on-device Foundation Models framework
/// (iOS 26+). The model is used the way the framework intends: guided
/// generation into typed `@Generable` structs, with tools for venue search
/// and travel times so its output stays grounded in real data — never
/// free-form chatbot text.
///
/// Candidate metrics (ETAs, fairness, budget) are computed deterministically
/// first; the model re-ranks the candidates and writes the one-line
/// explanations. If anything fails, we fall back to the heuristic ranking.
@available(iOS 26.0, *)
struct FoundationModelsEngine: SuggestionEngine {

    static var isModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    private let heuristic = HeuristicSuggestionEngine(maxResults: 10)

    func suggestions(for context: PlanningContext) async throws -> [MeetupSuggestion] {
        // Step 1: deterministic pipeline produces grounded, scored candidates.
        let candidates = try await heuristic.suggestions(for: context)
        guard candidates.count > 1 else { return candidates }

        // Step 2: the model re-ranks and explains, with tools available for
        // follow-up lookups (e.g. checking travel time to an alternative).
        do {
            let ranked = try await rerank(candidates: candidates, context: context)
            return ranked
        } catch {
            // Guardrail violations, context overflow, etc. — degrade gracefully.
            return Array(candidates.prefix(5))
        }
    }

    // MARK: - Guided generation

    @Generable
    struct RankedChoice {
        @Guide(description: "Index of the candidate in the provided list, starting at 0.")
        var candidateIndex: Int
        @Guide(description: "One friendly sentence explaining why this works for this specific group: fairness of travel, matched interests, budget. No emojis.")
        var explanation: String
    }

    @Generable
    struct RankedSuggestions {
        @Guide(description: "Best options first, at most 5. Use each candidate at most once.")
        var choices: [RankedChoice]
    }

    private func rerank(candidates: [MeetupSuggestion],
                        context: PlanningContext) async throws -> [MeetupSuggestion] {
        let session = LanguageModelSession(
            tools: [TravelTimeTool(participants: context.participants)],
            instructions: """
            You are Midway's meetup decision engine. You receive a meetup \
            request and pre-scored venue candidates. Rank the candidates so \
            the plan feels fair to every participant: balanced travel times \
            matter most, then shared interests, then budget. Be honest about \
            trade-offs in the explanations and mention concrete travel \
            minutes or interests when relevant. Never invent venues that are \
            not in the candidate list.
            """
        )

        let response = try await session.respond(
            to: prompt(for: candidates, context: context),
            generating: RankedSuggestions.self
        )

        var seen = Set<Int>()
        var result: [MeetupSuggestion] = []
        for choice in response.content.choices {
            guard candidates.indices.contains(choice.candidateIndex),
                  seen.insert(choice.candidateIndex).inserted else { continue }
            var suggestion = candidates[choice.candidateIndex]
            suggestion.explanation = choice.explanation
            result.append(suggestion)
        }
        // If the model dropped everything usable, keep the heuristic order.
        return result.isEmpty ? Array(candidates.prefix(5)) : Array(result.prefix(5))
    }

    private func prompt(for candidates: [MeetupSuggestion], context: PlanningContext) -> String {
        let request = context.request
        var lines: [String] = []
        lines.append("Meetup type: \(request.type.label). Proposed time window: \(request.timeWindow.kind.label).")
        if !request.constraints.vibe.isEmpty {
            lines.append("Requested vibe: \(request.constraints.vibe).")
        }
        if !request.constraints.dietaryNeeds.isEmpty {
            lines.append("Dietary needs: \(request.constraints.dietaryNeeds.joined(separator: ", ")).")
        }

        lines.append("Participants:")
        for p in context.participants {
            lines.append("- \(p.name): travels by \(p.transportMode.label.lowercased()), max \(p.maxTravelMinutes) min, budget \(p.budget.label), interests: \(p.interests.joined(separator: ", "))")
        }

        lines.append("Candidates:")
        for (index, c) in candidates.enumerated() {
            let times = context.participants.compactMap { p -> String? in
                guard let minutes = c.travelMinutesByParticipant[p.id] else { return nil }
                return "\(p.name) \(Int(minutes.rounded()))m"
            }.joined(separator: ", ")
            lines.append("\(index). \(c.venueName) (\(c.category), \(c.areaName)) — travel: \(times); fairness \(String(format: "%.2f", c.fairnessScore)), interest \(String(format: "%.2f", c.interestScore)), budget fit \(String(format: "%.2f", c.budgetFitScore))")
        }

        lines.append("Rank the best candidates for this group and explain each pick in one sentence.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Tools

/// Lets the model double-check a travel time for any participant to an
/// arbitrary coordinate while reasoning about trade-offs.
@available(iOS 26.0, *)
struct TravelTimeTool: Tool {
    let name = "travelTime"
    let description = "Estimate one-way travel minutes for a named participant to a latitude/longitude, using their preferred transport mode."

    let participants: [PlanningParticipant]
    private let routing = RoutingService()

    @Generable
    struct Arguments {
        @Guide(description: "Participant name exactly as given in the prompt.")
        var participantName: String
        var latitude: Double
        var longitude: Double
    }

    func call(arguments: Arguments) async throws -> String {
        guard let participant = participants.first(where: {
            $0.name.lowercased() == arguments.participantName.lowercased()
        }) else {
            return "Unknown participant \(arguments.participantName)."
        }
        let minutes = await routing.travelMinutes(
            from: participant.coordinate,
            to: Coordinate(latitude: arguments.latitude, longitude: arguments.longitude),
            mode: participant.transportMode
        )
        return "\(participant.name) would travel about \(Int(minutes.rounded())) minutes by \(participant.transportMode.label.lowercased())."
    }
}
#endif
