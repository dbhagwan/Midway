import AppIntents
import Foundation

/// "Plan a meetup" from Siri, Spotlight, or Shortcuts — drops the user
/// straight into the planner.
struct PlanMeetupIntent: AppIntent {
    static var title: LocalizedStringResource = "Plan a Meetup"
    static var description = IntentDescription(
        "Start a new Midway plan and get fair, AI-ranked places to meet your friends."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        // Route through the app's URL handler so the planner sheet opens.
        .result(opensIntent: OpenURLIntent(URL(string: "midway://plan")!))
    }
}

struct MidwayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlanMeetupIntent(),
            phrases: [
                "Plan a meetup in \(.applicationName)",
                "Find a place to meet with \(.applicationName)",
                "Start a \(.applicationName) plan",
            ],
            shortTitle: "Plan a meetup",
            systemImageName: "mappin.and.ellipse"
        )
    }
}
