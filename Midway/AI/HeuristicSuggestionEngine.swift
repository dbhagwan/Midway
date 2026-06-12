import Foundation

/// Deterministic suggestion engine. Always available: it is the fallback when
/// Apple's on-device model isn't (older OS, unsupported hardware, model not
/// downloaded), and it produces the same typed output as the AI path.
///
/// Pipeline: weighted midpoint -> venue search -> per-participant ETAs ->
/// fairness/interest/budget scoring -> templated explanations.
struct HeuristicSuggestionEngine: SuggestionEngine {
    var places = PlacesService()
    var routing = RoutingService()
    var maxResults = 5

    func suggestions(for context: PlanningContext) async throws -> [MeetupSuggestion] {
        let participants = context.participants
        guard let midpoint = MeetupScoring.weightedMidpoint(of: participants) else {
            throw SuggestionError.noParticipants
        }

        let venues = try await candidateVenues(for: context, near: midpoint)
        guard !venues.isEmpty else { throw SuggestionError.noVenuesFound }

        var scored: [MeetupSuggestion] = []
        for venue in venues {
            let travel = await travelTimes(to: venue, for: participants)

            // Respect a hard travel cap if the organizer set one.
            if let cap = context.request.constraints.maxTravelMinutes,
               let worst = travel.values.max(), worst > Double(cap) * 1.25 {
                continue
            }

            let fairness = MeetupScoring.fairness(travelMinutes: travel, participants: participants)
            let interest = MeetupScoring.interestMatch(venue: venue, participants: participants)
            let budget = MeetupScoring.budgetFit(venue: venue,
                                                 participants: participants,
                                                 cap: context.request.constraints.maxBudget)

            scored.append(MeetupSuggestion(
                venueName: venue.name,
                areaName: venue.areaName,
                category: venue.category,
                coordinate: venue.coordinate,
                travelMinutesByParticipant: travel,
                fairnessScore: fairness,
                interestScore: interest,
                budgetFitScore: budget,
                explanation: explanation(venue: venue, travel: travel,
                                         fairness: fairness, interest: interest,
                                         participants: participants),
                suggestedTime: context.request.timeWindow.suggestedTime()
            ))
        }

        return Array(scored.sorted { $0.overallScore > $1.overallScore }.prefix(maxResults))
    }

    // MARK: - Steps

    private func candidateVenues(for context: PlanningContext,
                                 near midpoint: Coordinate) async throws -> [Venue] {
        var query = context.request.type.searchQuery
        let constraints = context.request.constraints
        if !constraints.dietaryNeeds.isEmpty {
            query = "\(constraints.dietaryNeeds.joined(separator: " ")) \(query)"
        }
        if constraints.indoorOutdoor == .outdoor {
            query += " outdoor"
        }

        // Search radius scales with how far apart the group is.
        let spreadMeters = context.participants
            .map { $0.coordinate.distance(to: midpoint) }
            .max() ?? 2000
        let radius = min(max(spreadMeters * 0.5, 1500), 8000)

        return try await places.searchVenues(near: midpoint, query: query, radiusMeters: radius)
    }

    private func travelTimes(to venue: Venue,
                             for participants: [PlanningParticipant]) async -> [UUID: Double] {
        await withTaskGroup(of: (UUID, Double).self) { group in
            for participant in participants {
                group.addTask {
                    let minutes = await routing.travelMinutes(
                        from: participant.coordinate,
                        to: venue.coordinate,
                        mode: participant.transportMode
                    )
                    return (participant.id, minutes)
                }
            }
            var result: [UUID: Double] = [:]
            for await (id, minutes) in group { result[id] = minutes }
            return result
        }
    }

    private func explanation(venue: Venue,
                             travel: [UUID: Double],
                             fairness: Double,
                             interest: Double,
                             participants: [PlanningParticipant]) -> String {
        var parts: [String] = []

        if let maxTime = travel.values.max(), let minTime = travel.values.min() {
            let gap = Int((maxTime - minTime).rounded())
            if gap <= 5 {
                parts.append("nearly equal travel for everyone (~\(Int(maxTime.rounded())) min)")
            } else if fairness > 0.6 {
                parts.append("a fair split — at most \(Int(maxTime.rounded())) min for anyone")
            } else {
                parts.append("worth it despite uneven travel")
            }
        }

        if interest > 0.5 {
            let groupInterests = Set(participants.flatMap(\.interests).map { $0.lowercased() })
            let haystack = "\(venue.name) \(venue.category)".lowercased()
            if let match = groupInterests.first(where: { tag in
                tag.split(separator: " ").contains { haystack.contains($0.lowercased()) }
            }) {
                parts.append("matches the group's interest in \(match)")
            } else {
                parts.append("fits what this group usually likes")
            }
        }

        let summary = parts.isEmpty ? "a solid central option" : parts.joined(separator: ", and ")
        return "\(venue.name) in \(venue.areaName.isEmpty ? "the middle" : venue.areaName): \(summary)."
    }
}
