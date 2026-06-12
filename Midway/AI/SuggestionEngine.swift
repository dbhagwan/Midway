import Foundation

/// The AI in Midway is a decision engine, not a chatbot: it takes a typed
/// planning context and returns typed, scored suggestions.
protocol SuggestionEngine {
    func suggestions(for context: PlanningContext) async throws -> [MeetupSuggestion]
}

enum SuggestionError: LocalizedError {
    case noParticipants
    case noVenuesFound

    var errorDescription: String? {
        switch self {
        case .noParticipants: return "Nobody shared a location, so there's nothing to balance."
        case .noVenuesFound: return "No venues found near the group's midpoint. Try widening constraints."
        }
    }
}

/// Picks the best available engine: Apple's on-device Foundation Models when
/// the OS and hardware support it, otherwise the deterministic heuristic
/// engine. Both return the same typed output, so the UI doesn't care.
enum SuggestionEngineFactory {
    static func make() -> SuggestionEngine {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), FoundationModelsEngine.isModelAvailable {
            return FoundationModelsEngine()
        }
        #endif
        return HeuristicSuggestionEngine()
    }
}

// MARK: - Scoring

/// Pure scoring functions shared by both engines, kept separate so they are
/// unit-testable and so the model's explanations stay grounded in real math.
enum MeetupScoring {
    /// Travel-time fairness, 0...1. Penalizes both a wide spread between the
    /// luckiest and unluckiest traveler and anyone blowing past their own
    /// max travel tolerance.
    static func fairness(travelMinutes: [UUID: Double],
                         participants: [PlanningParticipant]) -> Double {
        let times = travelMinutes.values
        guard let maxTime = times.max(), let minTime = times.min(), !times.isEmpty else {
            return 0
        }
        // Spread component: a 0-minute gap scores 1, a 30+ minute gap scores 0.
        let spreadScore = max(0, 1 - (maxTime - minTime) / 30)

        // Tolerance component: fraction of the group within their own limit,
        // with partial credit for small overruns.
        let toleranceScores = participants.map { participant -> Double in
            guard let minutes = travelMinutes[participant.id] else { return 0 }
            let limit = Double(participant.maxTravelMinutes)
            if minutes <= limit { return 1 }
            return max(0, 1 - (minutes - limit) / limit)
        }
        let toleranceScore = toleranceScores.reduce(0, +) / Double(max(toleranceScores.count, 1))

        return spreadScore * 0.6 + toleranceScore * 0.4
    }

    /// Interest match, 0...1: how well a venue's name/category overlaps the
    /// union of the group's interest tags.
    static func interestMatch(venue: Venue, participants: [PlanningParticipant]) -> Double {
        let groupInterests = Set(participants.flatMap(\.interests).map { $0.lowercased() })
        guard !groupInterests.isEmpty else { return 0.5 }

        let haystack = "\(venue.name) \(venue.category) \(venue.areaName)".lowercased()
        let matched = groupInterests.filter { interest in
            interest.split(separator: " ").contains { haystack.contains($0.lowercased()) }
        }
        // A single strong match already feels personalized; saturate quickly.
        return min(1, Double(matched.count) / 2 + (matched.isEmpty ? 0 : 0.25))
    }

    /// Budget fit, 0...1, against the tightest budget in the group (or the
    /// request's explicit cap). Unknown venue prices score neutral.
    static func budgetFit(venue: Venue,
                          participants: [PlanningParticipant],
                          cap: BudgetRange?) -> Double {
        let groupCap = cap ?? participants.map(\.budget).min() ?? .medium
        guard let price = venue.priceLevel else { return 0.7 }
        if price <= groupCap { return 1 }
        return max(0, 1 - Double(price.rawValue - groupCap.rawValue) * 0.4)
    }

    /// Travel-time-weighted midpoint: slower travelers pull the center
    /// toward themselves so the meeting point is fair in minutes, not miles.
    static func weightedMidpoint(of participants: [PlanningParticipant]) -> Coordinate? {
        guard !participants.isEmpty else { return nil }
        let weights = participants.map { 1.0 / $0.transportMode.estimatedKmPerHour }
        let total = weights.reduce(0, +)
        let lat = zip(participants, weights).map { $0.coordinate.latitude * $1 }.reduce(0, +) / total
        let lon = zip(participants, weights).map { $0.coordinate.longitude * $1 }.reduce(0, +) / total
        return Coordinate(latitude: lat, longitude: lon)
    }
}
