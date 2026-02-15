import Foundation
import CryptoKit

enum DiscogsOAuthSigner {
    struct Credentials {
        let consumerKey: String
        let consumerSecret: String
        let oauthToken: String?
        let oauthTokenSecret: String?
    }

    enum SignerError: LocalizedError {
        case invalidRequestURL

        var errorDescription: String? {
            switch self {
            case .invalidRequestURL:
                return "Unable to sign Discogs request due to an invalid URL."
            }
        }
    }

    static func makeAuthorizationHeader(
        method: String,
        url: URL,
        credentials: Credentials,
        callback: String? = nil,
        verifier: String? = nil,
        nonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        timestamp: String = String(Int(Date().timeIntervalSince1970))
    ) throws -> String {
        let oauthParameters = makeOAuthParameters(
            credentials: credentials,
            callback: callback,
            verifier: verifier,
            nonce: nonce,
            timestamp: timestamp
        )

        let signature = try makeSignature(
            method: method,
            url: url,
            oauthParameters: oauthParameters,
            tokenSecret: credentials.oauthTokenSecret ?? "",
            consumerSecret: credentials.consumerSecret
        )

        var headerParams = oauthParameters
        headerParams["oauth_signature"] = signature

        let headerValue = headerParams
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(percentEncode(key))=\"\(percentEncode(value))\""
            }
            .joined(separator: ", ")

        return "OAuth \(headerValue)"
    }

    private static func makeOAuthParameters(
        credentials: Credentials,
        callback: String?,
        verifier: String?,
        nonce: String,
        timestamp: String
    ) -> [String: String] {
        var params: [String: String] = [
            "oauth_consumer_key": credentials.consumerKey,
            "oauth_nonce": nonce,
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": timestamp,
            "oauth_version": "1.0"
        ]

        if let token = credentials.oauthToken {
            params["oauth_token"] = token
        }
        if let callback {
            params["oauth_callback"] = callback
        }
        if let verifier {
            params["oauth_verifier"] = verifier
        }

        return params
    }

    private static func makeSignature(
        method: String,
        url: URL,
        oauthParameters: [String: String],
        tokenSecret: String,
        consumerSecret: String
    ) throws -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SignerError.invalidRequestURL
        }

        var signatureParameters = oauthParameters
        for item in components.queryItems ?? [] {
            signatureParameters[item.name] = item.value ?? ""
        }

        components.query = nil
        guard let baseURL = components.url else {
            throw SignerError.invalidRequestURL
        }

        var encodedPairs: [(String, String)] = []
        encodedPairs.reserveCapacity(signatureParameters.count)
        for (key, value) in signatureParameters {
            encodedPairs.append((percentEncode(key), percentEncode(value)))
        }
        let sortedPairs = encodedPairs.sorted { lhs, rhs in
            if lhs.0 == rhs.0 {
                return lhs.1 < rhs.1
            }
            return lhs.0 < rhs.0
        }
        let normalizedParameters = sortedPairs
            .map { pair in "\(pair.0)=\(pair.1)" }
            .joined(separator: "&")

        let signatureBase = [
            method.uppercased(),
            percentEncode(baseURL.absoluteString),
            percentEncode(normalizedParameters)
        ].joined(separator: "&")

        let signingKey = "\(percentEncode(consumerSecret))&\(percentEncode(tokenSecret))"
        let key = SymmetricKey(data: Data(signingKey.utf8))
        let digest = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(signatureBase.utf8),
            using: key
        )
        return Data(digest).base64EncodedString()
    }

    static func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
