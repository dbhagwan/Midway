import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showInterestEditor = false
    @State private var confirmingDeletion = false

    var body: some View {
        NavigationStack {
            if let profile = appState.profile {
                Form {
                    Section {
                        VStack(spacing: 10) {
                            AvatarView(name: profile.firstName,
                                       url: profile.auth.avatarURL,
                                       size: 88)
                            Text(profile.firstName).font(.title3.bold())
                            Text("@\(profile.username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(profile.auth.provider == .snapchat
                                 ? "Signed in with Snapchat" : "Demo account")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassEffect(.regular, in: .capsule)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }

                    Section("Getting around") {
                        Picker("Transport", selection: transportBinding) {
                            ForEach(TransportMode.allCases) { mode in
                                Label(mode.label, systemImage: mode.symbolName).tag(mode)
                            }
                        }
                        Stepper("Max travel: \(profile.maxTravelMinutes) min",
                                value: maxTravelBinding, in: 10...90, step: 5)
                        TextField("Home neighborhood", text: homeAreaBinding)
                    }

                    Section("Plans") {
                        Picker("Budget", selection: budgetBinding) {
                            ForEach(BudgetRange.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("Default location sharing", selection: sharingBinding) {
                            ForEach(LocationSharingLevel.allCases) { Text($0.label).tag($0) }
                        }
                    }

                    Section("Interests") {
                        if profile.interests.isEmpty {
                            Text("No interests yet").foregroundStyle(.secondary)
                        } else {
                            Text(profile.interests.joined(separator: " · "))
                                .font(.subheadline)
                        }
                        Button("Edit interests") { showInterestEditor = true }
                    }

                    Section {
                        Button("Sign out") {
                            appState.signOut()
                        }
                        Button("Delete account", role: .destructive) {
                            confirmingDeletion = true
                        }
                    } footer: {
                        Text("Deleting your account removes your profile, friends, and plans from Midway permanently. Snapchat only ever shares your display name, Bitmoji, and an ID with Midway.")
                    }
                    .confirmationDialog("Delete your Midway account?",
                                        isPresented: $confirmingDeletion,
                                        titleVisibility: .visible) {
                        Button("Delete everything", role: .destructive) {
                            Task { try? await appState.deleteAccount() }
                        }
                    } message: {
                        Text("This permanently deletes your profile, friend graph, and plans. Confirmed meetup cards your friends already have keep only your name.")
                    }
                }
                .onMidwayBackground()
                .navigationTitle("Profile")
                .sheet(isPresented: $showInterestEditor) {
                    InterestEditorView()
                }
            }
        }
    }

    // MARK: - Bindings that persist on change

    private func profileBinding<T>(_ keyPath: WritableKeyPath<UserProfile, T>,
                                   default defaultValue: T) -> Binding<T> {
        Binding(
            get: { appState.profile?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                appState.profile?[keyPath: keyPath] = newValue
                appState.saveProfile()
            }
        )
    }

    private var transportBinding: Binding<TransportMode> {
        profileBinding(\.transportMode, default: .transit)
    }
    private var maxTravelBinding: Binding<Int> {
        profileBinding(\.maxTravelMinutes, default: 30)
    }
    private var homeAreaBinding: Binding<String> {
        profileBinding(\.homeAreaName, default: "")
    }
    private var budgetBinding: Binding<BudgetRange> {
        profileBinding(\.budget, default: .medium)
    }
    private var sharingBinding: Binding<LocationSharingLevel> {
        profileBinding(\.defaultLocationSharing, default: .approximate)
    }
}

struct InterestEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                InterestTagGrid(selected: $selected)
                    .padding()
            }
            .navigationTitle("Interests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        appState.profile?.interests = Array(selected).sorted()
                        appState.saveProfile()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            selected = Set(appState.profile?.interests ?? [])
        }
    }
}

#Preview {
    ProfileView().environmentObject(AppState())
}
