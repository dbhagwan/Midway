import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            MidwayBackground()

            VStack(spacing: 20) {
                Spacer()

                GlassEffectContainer(spacing: 18) {
                    VStack(spacing: 18) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.midwayCoral)
                            .padding(26)
                            .glassEffect(.regular.tint(.midwayCoral.opacity(0.12)), in: .circle)

                        VStack(spacing: 10) {
                            Text("Midway")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                            Text("Find the best place to meet,\nwithout the group chat back-and-forth.")
                                .font(.headline)
                                .fontWeight(.regular)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .glassCard(cornerRadius: 32, padding: 24)
                    }
                }

                Spacer()

                Button {
                    signIn()
                } label: {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text(isSigningIn ? "Signing in…" : "Continue with Snapchat")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .disabled(isSigningIn)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Text("Snapchat shares only your display name, Bitmoji, and an ID. Your friends, interests, and location stay in Midway and are shared only when you choose.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
        }
    }

    private func signIn() {
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                try await appState.signIn()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}

#Preview {
    SignInView().environmentObject(AppState())
}
