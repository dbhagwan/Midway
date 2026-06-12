import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.isRestoring {
            ProgressView()
        } else if appState.profile == nil {
            SignInView()
        } else if !appState.hasCompletedOnboarding {
            OnboardingFlowView()
        } else {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showPlanner = false

    var body: some View {
        TabView {
            MeetupsListView(showPlanner: $showPlanner)
                .tabItem { Label("Meetups", systemImage: "mappin.and.ellipse") }

            FriendsView()
                .tabItem { Label("Friends", systemImage: "person.2.fill") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showPlanner) {
            NewMeetupView()
        }
        .onChange(of: appState.pendingPlannerRequest) { _, pending in
            if pending {
                showPlanner = true
                appState.pendingPlannerRequest = false
            }
        }
    }
}

#Preview {
    RootView().environmentObject(AppState())
}
