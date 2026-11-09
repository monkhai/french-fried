import AuthenticationServices
import CryptoKit
import Foundation
import Security

/// A one-time token and its raw nonce. Send both to the backend over TLS;
/// an Apple credential is not an authenticated backend session on its own.
public struct AppleIdentity {
    public let identityToken: String
    public let rawNonce: String
    public let appleUserID: String
    // Apple can provide these only on the initial authorization.
    public let fullName: PersonNameComponents?
    public let email: String?
}

public enum AppleSignInError: Error, Equatable {
    case cancelled
    case alreadyInProgress
    case secureRandomUnavailable
    case missingRequest
    case invalidCredential
    case missingIdentityToken
    case authorizationFailed
}

public enum AppleNonce {
    /// A cryptographically random nonce encoded as lower-case hexadecimal.
    public static func make() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AppleSignInError.secureRandomUnavailable
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(_ rawNonce: String) -> String {
        SHA256.hash(data: Data(rawNonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Retain one instance for the lifetime of the Apple sign-in UI.
/// It pairs each Apple response with the nonce for exactly that request.
@MainActor
public final class AppleSignInFlow {
    private var pendingNonce: String?

    public init() {}

    /// Called by SignInWithAppleButton's request closure. If setup fails, do not
    /// exchange any result; surface this error to the user from the host UI.
    public func configure(_ request: ASAuthorizationAppleIDRequest) throws {
        guard pendingNonce == nil else { throw AppleSignInError.alreadyInProgress }
        let nonce = try AppleNonce.make()
        pendingNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256(nonce)
    }

    /// Consume exactly one authorization result. On success the host must still
    /// exchange the token and nonce with its backend before showing a session.
    public func complete(_ result: Result<ASAuthorization, Error>) throws -> AppleIdentity {
        let nonce = pendingNonce
        pendingNonce = nil
        guard let nonce else { throw AppleSignInError.missingRequest }
        switch result {
        case .failure(let error):
            if let error = error as? ASAuthorizationError, error.code == .canceled {
                throw AppleSignInError.cancelled
            }
            throw AppleSignInError.authorizationFailed
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AppleSignInError.invalidCredential
            }
            guard let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8), !token.isEmpty else {
                throw AppleSignInError.missingIdentityToken
            }
            return AppleIdentity(identityToken: token, rawNonce: nonce,
                                 appleUserID: credential.user, fullName: credential.fullName,
                                 email: credential.email)
        }
    }
}
