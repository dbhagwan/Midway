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

                // The app icon, alive: a glass tile with the animated mark.
                AnimatedMeridianLogo(size: 200)
                    .glassEffect(.regular, in: .rect(cornerRadius: 45))

                VStack(spacing: 10) {
                    Text("Midway")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("Find the best place to meet,\nwithout the group chat back-and-forth.")
                        .font(.headline)
                        .fontWeight(.regular)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 14)

                Spacer()

                Button {
                    signIn(with: .snapchat)
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

                Button {
                    signIn(with: .apple)
                } label: {
                    HStack {
                        Image(systemName: "applelogo")
                        Text("Sign in with Apple")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent)
                .tint(.black)
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

    private func signIn(with provider: AuthProvider) {
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                try await appState.signIn(with: provider)
            } catch AuthError.cancelled {
                // No error banner for a user-cancelled sheet.
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
