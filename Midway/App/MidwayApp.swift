import SwiftUI
import UserNotifications
#if canImport(SCSDKLoginKit)
import SCSDKLoginKit
#endif

extension Notification.Name {
    static let midwayDeviceToken = Notification.Name("midwayDeviceToken")
    static let midwayPushTapped = Notification.Name("midwayPushTapped")
}

/// Receives APNs registration callbacks and routes notification taps.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Under XCUITest, continuous animations (map tiles, pulses) keep the
        // app from ever reporting idle, starving accessibility snapshots on
        // slow CI simulators. Plain -uiTestMode launches keep animations so
        // the CI video still captures the logo intro.
        if TestEnvironment.isXCTestRun {
            UIView.setAnimationsEnabled(false)
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .midwayDeviceToken, object: deviceToken)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        NotificationCenter.default.post(name: .midwayPushTapped,
                                        object: response.notification.request.content.userInfo)
    }
}

@main
struct MidwayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(.midwayCoral)
                .onOpenURL { url in
                    handle(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        handle(url: url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .midwayDeviceToken)) { note in
                    if let data = note.object as? Data {
                        appState.handleDeviceToken(data)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .midwayPushTapped)) { _ in
                    Task { await appState.refresh() }
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

        // Universal link: https://midway.app/add/<username>
        if url.host == "midway.app" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count == 2, parts[0] == "add" {
                appState.addFriend(username: parts[1])
            }
            return
        }
        // Custom-scheme invite links: midway://invite?from=<username>
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
