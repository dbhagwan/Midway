import SwiftUI
#if canImport(SCSDKLoginKit)
import SCSDKLoginKit
#endif

@main
struct MidwayApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(.midwayCoral)
                .onOpenURL { url in
                    handle(url: url)
                }
        }
    }

    private func handle(url: URL) {
        #if canImport(SCSDKLoginKit)
        // Snap Kit OAuth redirect (midway://snap-kit/oauth2).
        if SCSDKLoginClient.application(UIApplication.shared, open: url, options: [:]) {
            return
        }
        #endif
        // Invite links: midway://invite?from=<username>
        if url.host == "invite",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let from = components.queryItems?.first(where: { $0.name == "from" })?.value {
            appState.addFriend(username: from)
        }
        // App Intents route: midway://plan
        if url.host == "plan" {
            appState.pendingPlannerRequest = true
        }
    }
}
