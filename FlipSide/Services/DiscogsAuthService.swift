import Foundation
import AuthenticationServices
import UIKit

final class DiscogsAuthService: NSObject, ObservableObject {
    static let shared = DiscogsAuthService()

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isConnecting: Bool = false
    @Published private(set) var currentUsername: String?

    private let keychain = KeychainService.shared
    private let baseURL = "https://api.discogs.com"
    private let authorizeURL = "https://www.discogs.com/oauth/authorize"
    private let callbackURLString = "flipside://oauth/discogs"
    private let userAgent = "FlipSideApp/1.0"

    private var pendingRequestToken: String?
    private var pendingRequestTokenSecret: String?
    private var authSession: ASWebAuthenticationSession?

    enum AuthError: LocalizedError {
        case missingConsumerCredentials
        case notConnected
        case invalidState
        case invalidCallback
        case callbackMissingVerifier
        case userCancelled
        case apiError(Int, String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingConsumerCredentials:
                return "Discogs OAuth credentials are missing. Configure DISCOGS_CONSUMER_KEY and DISCOGS_CONSUMER_SECRET."
            case .notConnected:
                return "Discogs account is not connected. Connect in Settings."
            case .invalidState:
                return "Discogs OAuth state is invalid. Please try connecting again."
            case .invalidCallback:
                return "Invalid Discogs OAuth callback received."
            case .callbackMissingVerifier:
                return "Discogs OAuth callback did not include a verifier."
            case .userCancelled:
                return "Discogs connection was canceled."
            case let .apiError(code, message):
                return "Discogs OAuth failed (\(code)): \(message)"
            case .invalidResponse:
                return "Received an invalid response from Discogs OAuth."
            }
        }
    }

    struct ConsumerCredentials {
        let key: String
        let secret: String
    }

    private override init() {
        super.init()
        refreshPublishedState()
    }

    func connect() async throws {
        if isConnecting {
            return
        }

        await MainActor.run {
            self.isConnecting = true
        }
        defer {
            Task { @MainActor in
                self.isConnecting = false
            }
        }

        let temporaryToken = try await fetchRequestToken()

        pendingRequestToken = temporaryToken.token
        pendingRequestTokenSecret = temporaryToken.secret

        let callbackURL = try await presentAuthorizationSheet(requestToken: temporaryToken.token)
        try await handleCallback(url: callbackURL)
    }

    func handleCallback(url: URL) async throws {
        guard url.absoluteString.lowercased().hasPrefix(callbackURLString.lowercased()) else {
            throw AuthError.invalidCallback
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AuthError.invalidCallback
        }

        let callbackToken = components.queryItems?.first(where: { $0.name == "oauth_token" })?.value
        let verifier = components.queryItems?.first(where: { $0.name == "oauth_verifier" })?.value

        guard let expectedToken = pendingRequestToken,
              let requestSecret = pendingRequestTokenSecret,
              let callbackToken,
              expectedToken == callbackToken else {
            throw AuthError.invalidState
        }

        guard let verifier, !verifier.isEmpty else {
            throw AuthError.callbackMissingVerifier
        }

        let accessToken = try await fetchAccessToken(
            requestToken: callbackToken,
            requestTokenSecret: requestSecret,
            verifier: verifier
        )

        try keychain.setDiscogsOAuthToken(accessToken.token)
        try keychain.setDiscogsOAuthTokenSecret(accessToken.secret)

        let username = try await fetchIdentityUsername(
            oauthToken: accessToken.token,
            oauthTokenSecret: accessToken.secret
        )
        try keychain.setDiscogsUsername(username)

        pendingRequestToken = nil
        pendingRequestTokenSecret = nil
        refreshPublishedState()
    }

    func disconnect() throws {
        try keychain.delete(.discogsOAuthToken)
        try keychain.delete(.discogsOAuthTokenSecret)
        try keychain.delete(.discogsUsername)
        pendingRequestToken = nil
        pendingRequestTokenSecret = nil
        refreshPublishedState()
    }

    func authorizeRequest(_ request: inout URLRequest, callback: String? = nil, verifier: String? = nil) throws {
        let credentials = try oauthCredentials(
            callback: callback,
            verifier: verifier
        )
        guard let url = request.url else {
            throw AuthError.invalidResponse
        }
        let method = request.httpMethod ?? "GET"
        let header = try DiscogsOAuthSigner.makeAuthorizationHeader(
            method: method,
            url: url,
            credentials: credentials,
            callback: callback,
            verifier: verifier
        )
        request.setValue(header, forHTTPHeaderField: "Authorization")
    }

    func connectedUsername() -> String? {
        let username = keychain.discogsUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (username?.isEmpty == false) ? username : nil
    }

    func refreshPublishedState() {
        let username = connectedUsername()
        let connected = (keychain.discogsOAuthToken?.isEmpty == false) &&
            (keychain.discogsOAuthTokenSecret?.isEmpty == false) &&
            username != nil

        DispatchQueue.main.async {
            self.currentUsername = username
            self.isConnected = connected
        }
    }

    private func oauthCredentials(callback: String?, verifier: String?) throws -> DiscogsOAuthSigner.Credentials {
        let consumer = try consumerCredentials()

        if verifier != nil {
            guard let requestToken = pendingRequestToken else {
                throw AuthError.invalidState
            }
            return DiscogsOAuthSigner.Credentials(
                consumerKey: consumer.key,
                consumerSecret: consumer.secret,
                oauthToken: requestToken,
                oauthTokenSecret: pendingRequestTokenSecret
            )
        }

        if callback != nil {
            return DiscogsOAuthSigner.Credentials(
                consumerKey: consumer.key,
                consumerSecret: consumer.secret,
                oauthToken: nil,
                oauthTokenSecret: nil
            )
        }

        guard let token = keychain.discogsOAuthToken,
              let secret = keychain.discogsOAuthTokenSecret,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthError.notConnected
        }

        return DiscogsOAuthSigner.Credentials(
            consumerKey: consumer.key,
            consumerSecret: consumer.secret,
            oauthToken: token,
            oauthTokenSecret: secret
        )
    }

    private func consumerCredentials() throws -> ConsumerCredentials {
        let key = (Bundle.main.object(forInfoDictionaryKey: "DiscogsConsumerKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secret = (Bundle.main.object(forInfoDictionaryKey: "DiscogsConsumerSecret") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !key.isEmpty, !secret.isEmpty, !key.contains("$("), !secret.contains("$(") else {
            throw AuthError.missingConsumerCredentials
        }

        return ConsumerCredentials(key: key, secret: secret)
    }

    private func fetchRequestToken() async throws -> (token: String, secret: String) {
        guard let url = URL(string: "\(baseURL)/oauth/request_token") else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        try authorizeRequest(&request, callback: callbackURLString)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateAuthResponse(data: data, response: response)

        let values = parseFormEncoded(data)
        guard let token = values["oauth_token"],
              let secret = values["oauth_token_secret"] else {
            throw AuthError.invalidResponse
        }
        return (token: token, secret: secret)
    }

    private func fetchAccessToken(
        requestToken: String,
        requestTokenSecret: String,
        verifier: String
    ) async throws -> (token: String, secret: String) {
        pendingRequestToken = requestToken
        pendingRequestTokenSecret = requestTokenSecret

        guard let url = URL(string: "\(baseURL)/oauth/access_token") else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        try authorizeRequest(&request, verifier: verifier)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateAuthResponse(data: data, response: response)

        let values = parseFormEncoded(data)
        guard let token = values["oauth_token"],
              let secret = values["oauth_token_secret"] else {
            throw AuthError.invalidResponse
        }
        return (token: token, secret: secret)
    }

    private func fetchIdentityUsername(oauthToken: String, oauthTokenSecret: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/oauth/identity") else {
            throw AuthError.invalidResponse
        }

        let consumer = try consumerCredentials()
        let credentials = DiscogsOAuthSigner.Credentials(
            consumerKey: consumer.key,
            consumerSecret: consumer.secret,
            oauthToken: oauthToken,
            oauthTokenSecret: oauthTokenSecret
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            try DiscogsOAuthSigner.makeAuthorizationHeader(
                method: "GET",
                url: url,
                credentials: credentials
            ),
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateAuthResponse(data: data, response: response)

        let decoder = JSONDecoder()
        let identity = try decoder.decode(IdentityResponse.self, from: data)
        let username = identity.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            throw AuthError.invalidResponse
        }
        return username
    }

    private func presentAuthorizationSheet(requestToken: String) async throws -> URL {
        guard var components = URLComponents(string: authorizeURL) else {
            throw AuthError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "oauth_token", value: requestToken)]

        guard let authURL = components.url else {
            throw AuthError.invalidResponse
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                self.authSession = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: "flipside"
                ) { callbackURL, error in
                    self.authSession = nil
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else if let asError = error as? ASWebAuthenticationSessionError,
                              asError.code == .canceledLogin {
                        continuation.resume(throwing: AuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: error ?? AuthError.invalidCallback)
                    }
                }
                self.authSession?.presentationContextProvider = self
                self.authSession?.prefersEphemeralWebBrowserSession = true
                if !(self.authSession?.start() ?? false) {
                    continuation.resume(throwing: AuthError.invalidState)
                }
            }
        }
    }

    private func validateAuthResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.apiError(httpResponse.statusCode, body)
        }
    }

    private func parseFormEncoded(_ data: Data) -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var dict: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let keyPart = parts.first else { continue }
            let valuePart = parts.count > 1 ? String(parts[1]) : ""
            let key = String(keyPart).removingPercentEncoding ?? String(keyPart)
            let value = valuePart.removingPercentEncoding ?? valuePart
            dict[key] = value
        }
        return dict
    }
}

private extension DiscogsAuthService {
    struct IdentityResponse: Decodable {
        let username: String
    }
}

extension DiscogsAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
