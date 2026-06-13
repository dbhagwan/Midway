import Foundation
import UIKit
#if canImport(SCSDKLoginKit)
import SCSDKLoginKit
#endif

enum AuthError: LocalizedError {
    case cancelled
    case noPresenter
    case snapKitUnavailable
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Sign-in was cancelled."
        case .noPresenter: return "Could not find a window to present sign-in."
        case .snapKitUnavailable: return "Snapchat sign-in isn't configured in this build."
        case .underlying(let error): return error.localizedDescription
        }
    }
}

protocol AuthService {
    /// Whether this provider can run in the current build/configuration.
    var isAvailable: Bool { get }
    func signIn() async throws -> AuthenticatedUser
    func signOut()
}

// MARK: - Snapchat Login Kit

/// Wraps Snap Kit's Login Kit. Snap exposes only display name, Bitmoji
/// avatar, and an external user ID — Midway treats Snapchat purely as an
/// identity layer and owns everything else.
final class SnapchatAuthService: AuthService {
    var isAvailable: Bool {
        #if canImport(SCSDKLoginKit)
        let clientID = Bundle.main.object(forInfoDictionaryKey: "SCSDKClientId") as? String
        return clientID?.isEmpty == false && clientID != "YOUR_SNAP_KIT_CLIENT_ID"
        #else
        return false
        #endif
    }

    @MainActor
    func signIn() async throws -> AuthenticatedUser {
        #if canImport(SCSDKLoginKit)
        guard let presenter = Self.topViewController() else { throw AuthError.noPresenter }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            SCSDKLoginClient.login(from: presenter) { success, error in
                if let error {
                    continuation.resume(throwing: AuthError.underlying(error))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AuthError.cancelled)
                }
            }
        }
        return try await fetchSnapIdentity()
        #else
        throw AuthError.snapKitUnavailable
        #endif
    }

    func signOut() {
        #if canImport(SCSDKLoginKit)
        SCSDKLoginClient.clearToken()
        #endif
    }

    #if canImport(SCSDKLoginKit)
    private func fetchSnapIdentity() async throws -> AuthenticatedUser {
        let query = SCSDKUserDataQueryBuilder()
            .withDisplayName()
            .withBitmojiTwoDAvatarUrl()
            .withExternalId()
            .build()

        return try await withCheckedThrowingContinuation { continuation in
            SCSDKLoginClient.fetchUserData(with: query) { userData, _ in
                let user = AuthenticatedUser(
                    providerUserID: userData?.externalID ?? UUID().uuidString,
                    provider: .snapchat,
                    displayName: userData?.displayName ?? "Snapchatter",
                    avatarURL: (userData?.bitmojiTwoDAvatarUrl).flatMap(URL.init(string:)),
                    credential: SCSDKLoginClient.getAccessToken()
                )
                continuation.resume(returning: user)
            } failure: { error, _ in
                continuation.resume(throwing: AuthError.underlying(
                    error ?? AuthError.snapKitUnavailable))
            }
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let root = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
    #endif
}

// MARK: - Mock provider

/// Lets the app run end-to-end without Snap Kit credentials (simulator,
/// demos, UI tests). Swap automatically when SCSDKClientId isn't set.
final class MockAuthService: AuthService {
    var isAvailable: Bool { true }

    func signIn() async throws -> AuthenticatedUser {
        try? await Task.sleep(for: .milliseconds(400))
        return AuthenticatedUser(
            providerUserID: "mock-user-1",
            provider: .mock,
            displayName: "Demo User",
            avatarURL: nil
        )
    }

    func signOut() {}
}
