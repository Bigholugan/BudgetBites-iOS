import Foundation
import AuthenticationServices
import CryptoKit

public final class KrogerAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = KrogerAuthManager()
    
    private var authSession: ASWebAuthenticationSession?
    private var presentationAnchor: ASPresentationAnchor?
    
    private override init() {
        super.init()
    }
    
    public enum AuthError: LocalizedError {
        case userCancelled
        case missingAuthCode
        case tokenExchangeFailed(String)
        case invalidState
        
        public var errorDescription: String? {
            switch self {
            case .userCancelled:
                return "Kroger sign-in was cancelled."
            case .missingAuthCode:
                return "Failed to receive authorization code from Kroger."
            case .tokenExchangeFailed(let msg):
                return "Kroger token exchange failed: \(msg)"
            case .invalidState:
                return "Invalid OAuth state returned."
            }
        }
    }
    
    // MARK: - PKCE Helpers
    public static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    public static func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    // MARK: - Start Sign-in Flow
    public func authenticate(
        backendBaseURL: String,
        clientId: String,
        redirectUri: String,
        anchor: ASPresentationAnchor
    ) async throws -> String {
        self.presentationAnchor = anchor
        let verifier = Self.generateCodeVerifier()
        let challenge = Self.generateCodeChallenge(from: verifier)
        let state = UUID().uuidString
        
        var components = URLComponents(string: "https://api.kroger.com/v1/connect/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "scope", value: "cart.basic:write profile.compact"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        
        guard let authURL = components.url else {
            throw AuthError.missingAuthCode
        }
        
        // Start ASWebAuthenticationSession
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "budgetbites"
            ) { callback, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.userCancelled)
                    return
                }
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callback = callback else {
                    continuation.resume(throwing: AuthError.missingAuthCode)
                    return
                }
                continuation.resume(returning: callback)
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
        
        // Extract auth code from callback URL
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.missingAuthCode
        }
        
        // Exchange code via backend
        return try await exchangeCodeViaBackend(
            backendBaseURL: backendBaseURL,
            code: code,
            verifier: verifier,
            redirectUri: redirectUri
        )
    }
    
    private func exchangeCodeViaBackend(
        backendBaseURL: String,
        code: String,
        verifier: String,
        redirectUri: String
    ) async throws -> String {
        guard let url = URL(string: "\(backendBaseURL)/api/kroger/oauth/token") else {
            throw AuthError.tokenExchangeFailed("Invalid backend URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectUri
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw AuthError.tokenExchangeFailed(errorMsg)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw AuthError.tokenExchangeFailed("Missing access_token in response")
        }
        
        let refreshToken = json["refresh_token"] as? String ?? ""
        let expiresIn = json["expires_in"] as? Double ?? 1800
        let expirationDate = Date().addingTimeInterval(expiresIn)
        
        // Securely persist in iOS Keychain
        KeychainManager.shared.saveString(accessToken, forKey: .accessToken)
        if !refreshToken.isEmpty {
            KeychainManager.shared.saveString(refreshToken, forKey: .refreshToken)
        }
        KeychainManager.shared.saveString(String(expirationDate.timeIntervalSince1970), forKey: .tokenExpiration)
        
        return accessToken
    }
    
    // MARK: - ASWebAuthenticationPresentationContextProviding
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let anchor = presentationAnchor {
            return anchor
        }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
