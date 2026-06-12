import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(28)
                .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .circle)

            Text("Midway")
                .font(.system(size: 44, weight: .bold, design: .rounded))

            Text("Find the best place to meet,\nwithout the group chat back-and-forth.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

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
