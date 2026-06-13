import AuthenticationServices
import UIKit

/// Sign in with Apple — required by App Review (guideline 4.8) for any app
/// offering third-party login. Apple provides full name only on the very
/// first authorization, so we fall back to a friendly default after that.
final class AppleAuthService: NSObject, AuthService {
    private var continuation: CheckedContinuation<AuthenticatedUser, Error>?

    var isAvailable: Bool { true }

    @MainActor
    func signIn() async throws -> AuthenticatedUser {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func signOut() {}
}

extension AppleAuthService: ASAuthorizationControllerDelegate,
                            ASAuthorizationControllerPresentationContextProviding {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AuthError.cancelled)
            continuation = nil
            return
        }
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        continuation?.resume(returning: AuthenticatedUser(
            providerUserID: credential.user,
            provider: .apple,
            displayName: name.isEmpty ? "Midway friend" : name,
            avatarURL: nil,
            credential: credential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
        ))
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(throwing: AuthError.cancelled)
        } else {
            continuation?.resume(throwing: AuthError.underlying(error))
        }
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
