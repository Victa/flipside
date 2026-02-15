//
//  DiscogsCollectionService.swift
//  FlipSide
//
//  Service for managing Discogs user collection and wantlist operations.
//

import Foundation

/// Service for checking and managing user's Discogs collection and wantlist
final class DiscogsCollectionService {
    
    // MARK: - Configuration
    
    private let baseURL = "https://api.discogs.com"
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0
    
    // Rate limiting (reuse from DiscogsService pattern)
    private let rateLimitDelay: TimeInterval = 0.2 // 60 requests/minute
    private var lastRequestTime: Date?
    private let rateLimitQueue = DispatchQueue(label: "com.flipside.discogs.collection.ratelimit")
    
    // MARK: - Error Types
    
    enum CollectionError: LocalizedError {
        case notConnected
        case noUsername
        case invalidURL
        case networkError(Error)
        case apiError(statusCode: Int, message: String)
        case invalidResponse
        case parsingError(String)
        case rateLimitExceeded
        case notFound
        
        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Discogs account not connected. Connect your account in Settings."
            case .noUsername:
                return "Discogs username not configured. Please add your username in Settings."
            case .invalidURL:
                return "Invalid API URL constructed."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .apiError(let statusCode, let message):
                return "Discogs API error (\(statusCode)): \(message)"
            case .invalidResponse:
                return "Received an invalid response from the Discogs API."
            case .parsingError(let details):
                return "Failed to parse Discogs response: \(details)"
            case .rateLimitExceeded:
                return "Discogs API rate limit exceeded. Please wait a moment and try again."
            case .notFound:
                return "Release not found in collection or wantlist."
            }
        }
    }
    
    // MARK: - Response Models
    
    private struct CollectionResponse: Codable {
        let pagination: Pagination?
        let releases: [CollectionRelease]?
        
        struct Pagination: Codable {
            let page: Int
            let pages: Int
            let items: Int
            let perPage: Int?
            
            enum CodingKeys: String, CodingKey {
                case page, pages, items
                case perPage = "per_page"
            }
        }
        
        struct CollectionRelease: Codable {
            let id: Int
            let instanceId: Int
            let basicInformation: BasicInfo?
            
            enum CodingKeys: String, CodingKey {
                case id
                case instanceId = "instance_id"
                case basicInformation = "basic_information"
            }
            
            struct BasicInfo: Codable {
                let id: Int
            }
        }
    }
    
    private struct WantlistResponse: Codable {
        let wants: [WantlistItem]?
        let pagination: Pagination?
        
        struct WantlistItem: Codable {
            let id: Int
            let basicInformation: BasicInfo?
            
            enum CodingKeys: String, CodingKey {
                case id
                case basicInformation = "basic_information"
            }
            
            struct BasicInfo: Codable {
                let id: Int
            }
        }
        
        struct Pagination: Codable {
            let page: Int
            let pages: Int
            let items: Int
        }
    }
    
    // MARK: - Singleton
    
    static let shared = DiscogsCollectionService()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Check if a release is in user's collection and/or wantlist
    /// - Parameters:
    ///   - releaseId: The Discogs release ID to check
    ///   - username: The Discogs username
    /// - Returns: Tuple with collection and wantlist status
    /// - Throws: CollectionError if check fails
    func checkCollectionStatus(releaseId: Int, username: String) async throws -> (isInCollection: Bool, isInWantlist: Bool) {
        guard DiscogsAuthService.shared.isConnected else {
            throw CollectionError.notConnected
        }
        
        guard !username.isEmpty else {
            throw CollectionError.noUsername
        }
        
        // Check both collection and wantlist concurrently
        async let collectionCheck = isInCollection(releaseId: releaseId, username: username)
        async let wantlistCheck = isInWantlist(releaseId: releaseId, username: username)
        
        let (inCollection, inWantlist) = try await (collectionCheck, wantlistCheck)
        
        return (isInCollection: inCollection, isInWantlist: inWantlist)
    }
    
    /// Add a release to the user's collection
    /// - Parameters:
    ///   - releaseId: The Discogs release ID
    ///   - username: The Discogs username
    /// - Throws: CollectionError if operation fails
    func addToCollection(releaseId: Int, username: String) async throws {
        guard DiscogsAuthService.shared.isConnected else {
            throw CollectionError.notConnected
        }
        
        guard !username.isEmpty else {
            throw CollectionError.noUsername
        }
        
        // Apply rate limiting
        await applyRateLimit()
        
        // Folder ID 1 is the default "Uncategorized" folder
        guard let url = URL(string: "\(baseURL)/users/\(username)/collection/folders/1/releases/\(releaseId)") else {
            throw CollectionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        try DiscogsAuthService.shared.authorizeRequest(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("FlipSideApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        try validateHTTPResponse(response)
    }
    
    /// Remove a release from the user's collection
    /// - Parameters:
    ///   - releaseId: The Discogs release ID
    ///   - username: The Discogs username
    /// - Throws: CollectionError if operation fails
    func removeFromCollection(releaseId: Int, username: String) async throws {
        guard DiscogsAuthService.shared.isConnected else {
            throw CollectionError.notConnected
        }
        
        guard !username.isEmpty else {
            throw CollectionError.noUsername
        }
        
        // First, get the instance ID
        guard let instanceId = try await getCollectionInstanceId(releaseId: releaseId, username: username) else {
            throw CollectionError.notFound
        }
        
        // Apply rate limiting
        await applyRateLimit()
        
        // Folder ID 1 is the default "Uncategorized" folder
        guard let url = URL(string: "\(baseURL)/users/\(username)/collection/folders/1/releases/\(releaseId)/instances/\(instanceId)") else {
            throw CollectionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        try DiscogsAuthService.shared.authorizeRequest(&request)
        request.setValue("FlipSideApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        try validateHTTPResponse(response, allowNoContent: true)
    }
    
    /// Add a release to the user's wantlist
    /// - Parameters:
    ///   - releaseId: The Discogs release ID
    ///   - username: The Discogs username
    /// - Throws: CollectionError if operation fails
    func addToWantlist(releaseId: Int, username: String) async throws {
        guard DiscogsAuthService.shared.isConnected else {
            throw CollectionError.notConnected
        }
        
        guard !username.isEmpty else {
            throw CollectionError.noUsername
        }
        
        // Apply rate limiting
        await applyRateLimit()
        
        guard let url = URL(string: "\(baseURL)/users/\(username)/wants/\(releaseId)") else {
            throw CollectionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        try DiscogsAuthService.shared.authorizeRequest(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("FlipSideApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        try validateHTTPResponse(response)
    }
    
    /// Remove a release from the user's wantlist
    /// - Parameters:
    ///   - releaseId: The Discogs release ID
    ///   - username: The Discogs username
    /// - Throws: CollectionError if operation fails
    func removeFromWantlist(releaseId: Int, username: String) async throws {
        guard DiscogsAuthService.shared.isConnected else {
            throw CollectionError.notConnected
        }
        
        guard !username.isEmpty else {
            throw CollectionError.noUsername
        }
        
        // Apply rate limiting
        await applyRateLimit()
        
        guard let url = URL(string: "\(baseURL)/users/\(username)/wants/\(releaseId)") else {
            throw CollectionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        try DiscogsAuthService.shared.authorizeRequest(&request)
        request.setValue("FlipSideApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        try validateHTTPResponse(response, allowNoContent: true)
    }
    
    // MARK: - Private Methods
    
    /// Check if release is in user's collection using per-release endpoint
    private func isInCollection(releaseId: Int, username: String) async throws -> Bool {
        // Apply rate limiting
        await applyRateLimit()
        
        // Use the per-release collection endpoint (release_id as path parameter)
        guard let url = URL(string: "\(baseURL)/users/\(username)/collection/releases/\(releaseId)") else {
            throw CollectionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        try DiscogsAuthService.shared.authorizeRequest(&request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FlipSideApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let httpCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        
        // 404 means release is not in collection
        if httpCode == 404 {
            return false
        }
        
        try validateHTTPResponse(response)
        
        // If we got a 200, check if there are actual release instances
        let decoder = JSONDecoder()
        do {
            let collectionResponse = try decoder.decode(CollectionResponse.self, from: data)
            let hasReleases = collectionResponse.releases != nil && !collectionResponse.releases!.isEmpty
            return hasReleases
        } catch {
            throw CollectionError.parsingError("Failed to decode collection response: \(error.localizedDescription)")
        }
    }
    
    /// Check if release is in user's wantlist using per-release endpoint
    private func isInWantlist(releaseId: Int, username: String) async throws -> Bool {
        // Apply rate limiting
        await applyRateLimit()
        
        // Use the per-release wantlist endpoint (release_id as path parameter)
        guard let url = URL(string: "\(baseURL)/users/\(username)/wants/\(releaseId)") else {
            throw CollectionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        try DiscogsAuthService.shared.authorizeRequest(&request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FlipSideApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        let httpCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        
        // 404 means release is not in wantlist
        if httpCode == 404 {
            return false
        }
        
        try validateHTTPResponse(response)
        
        // 200 means the release is in the wantlist
        return true
    }
    
    /// Get the instance ID for a release in the collection (needed for deletion)
    private func getCollectionInstanceId(releaseId: Int, username: String) async throws -> Int? {
        // Apply rate limiting
        await applyRateLimit()
        
        // Use the per-release collection endpoint to find instances
        guard let url = URL(string: "\(baseURL)/users/\(username)/collection/releases/\(releaseId)") else {
            throw CollectionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        try DiscogsAuthService.shared.authorizeRequest(&request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FlipSideApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let httpCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        if httpCode == 404 {
            return nil
        }
        
        try validateHTTPResponse(response)
        
        let decoder = JSONDecoder()
        do {
            let collectionResponse = try decoder.decode(CollectionResponse.self, from: data)
            
            // Return the first instance ID found
            return collectionResponse.releases?.first?.instanceId
        } catch {
            throw CollectionError.parsingError("Failed to decode collection response: \(error.localizedDescription)")
        }
    }
    
    /// Apply rate limiting by waiting if necessary
    private func applyRateLimit() async {
        rateLimitQueue.sync {
            if let lastRequest = lastRequestTime {
                let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
                if timeSinceLastRequest < rateLimitDelay {
                    let waitTime = rateLimitDelay - timeSinceLastRequest
                    Thread.sleep(forTimeInterval: waitTime)
                }
            }
            lastRequestTime = Date()
        }
    }
    
    /// Validate HTTP response status code
    private func validateHTTPResponse(_ response: URLResponse, allowNoContent: Bool = false) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CollectionError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return
            
        case 204 where allowNoContent:
            return
            
        case 401:
            try? DiscogsAuthService.shared.disconnect()
            throw CollectionError.apiError(
                statusCode: 401,
                message: "OAuth authentication failed. Please reconnect your Discogs account in Settings."
            )
            
        case 404:
            throw CollectionError.notFound
            
        case 429:
            throw CollectionError.rateLimitExceeded
            
        case 500...599:
            throw CollectionError.apiError(
                statusCode: httpResponse.statusCode,
                message: "Discogs server error"
            )
            
        default:
            throw CollectionError.apiError(
                statusCode: httpResponse.statusCode,
                message: "Unexpected response status"
            )
        }
    }
}
