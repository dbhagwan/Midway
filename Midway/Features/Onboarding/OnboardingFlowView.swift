import SwiftUI

/// Three-step onboarding: basics -> interests -> privacy defaults.
/// Everything collected here feeds the ranking engine directly.
struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState

    @State private var step = 0
    @State private var firstName = ""
    @State private var username = ""
    @State private var homeArea = ""
    @State private var transport: TransportMode = .transit
    @State private var maxTravel = 30
    @State private var budget: BudgetRange = .medium
    @State private var meetupTypes: Set<MeetupType> = [.coffee, .drinks]
    @State private var interests: Set<String> = []
    @State private var sharingDefault: LocationSharingLevel = .approximate

    var body: some View {
        NavigationStack {
            TabView(selection: $step) {
                basicsStep.tag(0)
                interestsStep.tag(1)
                privacyStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .background(MidwayBackground())
            .navigationTitle("Set up Midway")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    if step < 2 {
                        withAnimation { step += 1 }
                    } else {
                        finish()
                    }
                } label: {
                    Text(step < 2 ? "Continue" : "Start meeting up")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .disabled(step == 0 && firstName.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding()
            }
        }
        .onAppear {
            firstName = appState.profile?.auth.displayName ?? ""
        }
    }

    // MARK: Step 1 — basics

    private var basicsStep: some View {
        styledForm {
            Section("About you") {
                TextField("First name", text: $firstName)
                TextField("Midway username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Home neighborhood (e.g. Mission District)", text: $homeArea)
            }
            Section("Getting around") {
                Picker("Usual transport", selection: $transport) {
                    ForEach(TransportMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbolName).tag(mode)
                    }
                }
                Stepper("Max travel: \(maxTravel) min", value: $maxTravel, in: 10...90, step: 5)
            }
            Section("Typical plans") {
                Picker("Budget", selection: $budget) {
                    ForEach(BudgetRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                ForEach(MeetupType.allCases) { type in
                    Toggle(isOn: binding(for: type)) {
                        Label(type.label, systemImage: type.symbolName)
                    }
                }
            }
        }
    }

    private func binding(for type: MeetupType) -> Binding<Bool> {
        Binding(
            get: { meetupTypes.contains(type) },
            set: { isOn in
                if isOn { meetupTypes.insert(type) } else { meetupTypes.remove(type) }
            }
        )
    }

    // MARK: Step 2 — interests

    private var interestsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What does a good meetup spot look like?")
                    .font(.title2.bold())
                Text("Pick a few interests. Midway uses them to rank suggestions for your groups.")
                    .foregroundStyle(.secondary)

                InterestTagGrid(selected: $interests)
            }
            .padding()
        }
    }

    // MARK: Step 3 — privacy

    private var privacyStep: some View {
        styledForm {
            Section {
                Picker("Default location sharing", selection: $sharingDefault) {
                    ForEach(LocationSharingLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Location privacy")
            } footer: {
                Text("Midway asks for location only while planning a meetup, and you can override this choice every time. Nothing is shared in the background.")
            }
        }
    }

    private func styledForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form { content() }
            .scrollContentBackground(.hidden)
    }

    private func finish() {
        guard var profile = appState.profile else { return }
        profile.firstName = firstName.trimmingCharacters(in: .whitespaces)
        profile.username = username.isEmpty
            ? firstName.lowercased().filter { $0.isLetter }
            : username.lowercased()
        profile.homeAreaName = homeArea
        profile.transportMode = transport
        profile.maxTravelMinutes = maxTravel
        profile.budget = budget
        profile.favoriteMeetupTypes = meetupTypes
        profile.interests = Array(interests).sorted()
        profile.defaultLocationSharing = sharingDefault
        appState.completeOnboarding(with: profile)
    }
}

/// Reusable flowing grid of selectable interest chips.
struct InterestTagGrid: View {
    @Binding var selected: Set<String>
    var tags: [String] = InterestTag.presets

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    let isOn = selected.contains(tag)
                    Button {
                        withAnimation(.snappy) {
                            if isOn { selected.remove(tag) } else { selected.insert(tag) }
                        }
                    } label: {
                        Text(tag)
                            .font(.subheadline)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(isOn ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        isOn ? .regular.tint(.accentColor).interactive()
                             : .regular.interactive(),
                        in: .capsule
                    )
                }
            }
        }
    }
}

#Preview {
    OnboardingFlowView().environmentObject(AppState())
}
