import Foundation

// MARK: - Planning

/// Extra constraints an organizer can attach to a meetup request.
struct MeetupConstraints: Codable, Hashable {
    var maxBudget: BudgetRange?
    var indoorOutdoor: IndoorOutdoor = .either
    var dietaryNeeds: [String] = []
    /// Free-form vibe, e.g. "lowkey", "lively", "good for talking".
    var vibe: String = ""
    /// Hard cap on any participant's one-way travel, in minutes.
    var maxTravelMinutes: Int?

    enum IndoorOutdoor: String, Codable, CaseIterable, Identifiable {
        case indoor, outdoor, either
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
}

/// A request to meet: who, what kind, when, and under which constraints.
struct MeetupRequest: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var organizerID: UUID
    var participantFriendIDs: [UUID]
    var type: MeetupType
    var timeWindow: TimeWindow
    var constraints: MeetupConstraints = MeetupConstraints()
    var createdAt: Date = Date()
}

/// Per-participant answer to a meetup request: availability plus the
/// location context they consented to share for this session only.
struct ParticipantResponse: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var participantID: UUID
    var isAvailable: Bool
    var sharingLevel: LocationSharingLevel
    var coordinate: Coordinate?
    var manualPlaceName: String?
}

/// A fully resolved participant fed into the suggestion engine:
/// identity + preferences + the location context for this session.
struct PlanningParticipant: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var transportMode: TransportMode
    var maxTravelMinutes: Int
    var budget: BudgetRange
    var interests: [String]
    var coordinate: Coordinate
}

/// Everything the suggestion engine needs to rank options.
struct PlanningContext: Codable, Hashable {
    var request: MeetupRequest
    var participants: [PlanningParticipant]
}

// MARK: - Suggestions

/// One ranked option produced by the suggestion engine. All scores are 0...1.
struct MeetupSuggestion: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var venueName: String
    var areaName: String
    var category: String
    var coordinate: Coordinate
    /// One-way travel minutes keyed by participant ID.
    var travelMinutesByParticipant: [UUID: Double]
    var fairnessScore: Double
    var interestScore: Double
    var budgetFitScore: Double
    var explanation: String
    var suggestedTime: Date

    var overallScore: Double {
        fairnessScore * 0.45 + interestScore * 0.3 + budgetFitScore * 0.25
    }

    var longestTravelMinutes: Double {
        travelMinutesByParticipant.values.max() ?? 0
    }
}

// MARK: - Confirmed meetups

/// The card created once the group picks a suggestion.
struct Meetup: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var venueName: String
    var areaName: String
    var coordinate: Coordinate
    var time: Date
    var attendeeNames: [String]
    var explanation: String
    var createdAt: Date = Date()

    init(suggestion: MeetupSuggestion, type: MeetupType, attendeeNames: [String]) {
        self.title = "\(type.label) at \(suggestion.venueName)"
        self.venueName = suggestion.venueName
        self.areaName = suggestion.areaName
        self.coordinate = suggestion.coordinate
        self.time = suggestion.suggestedTime
        self.attendeeNames = attendeeNames
        self.explanation = suggestion.explanation
    }
}

// MARK: - Venues

/// A candidate place returned by the places service.
struct Venue: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var category: String
    var areaName: String
    var coordinate: Coordinate
    /// Best-effort price level when the source exposes one.
    var priceLevel: BudgetRange?
}
