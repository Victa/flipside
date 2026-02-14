//
//  DiscogsService.swift
//  FlipSide
//
//  Discogs API client for searching releases and fetching pricing data.
//

import Foundation

/// Service for interacting with the Discogs API
final class DiscogsService {
    
    // MARK: - Configuration
    
    private let baseURL = "https://api.discogs.com"
    private let searchEndpoint = "/database/search"
    private let releaseEndpoint = "/releases"
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0
    private let maxResultsPerSearch = 10
    
    // Rate limiting configuration
    private let rateLimitDelay: TimeInterval = 1.0 // 60 requests/minute = 1 per second
    private var lastRequestTime: Date?
    private let rateLimitQueue = DispatchQueue(label: "com.flipside.discogs.ratelimit")
    
    // MARK: - Error Types
    
    enum DiscogsError: LocalizedError {
        case noPersonalToken
        case invalidURL
        case networkError(Error)
        case apiError(statusCode: Int, message: String)
        case invalidResponse
        case parsingError(String)
        case rateLimitExceeded
        case retryLimitExceeded
        case noMatches
        
        var errorDescription: String? {
            switch self {
            case .noPersonalToken:
                return "Discogs personal access token not found. Please configure it in Settings."
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
            case .retryLimitExceeded:
                return "Maximum retry attempts exceeded. Please try again later."
            case .noMatches:
                return "No matching releases found in Discogs database."
            }
        }
    }
    
    // MARK: - Response Models
    
    private struct SearchResponse: Codable {
        let results: [SearchResult]
        let pagination: Pagination?
        
        struct SearchResult: Codable {
            let id: Int
            let type: String
            let title: String
            let year: String?
            let label: [String]?
            let catno: String?
            let genre: [String]?
            let coverImage: String?
            
            enum CodingKeys: String, CodingKey {
                case id, type, title, year, label, catno, genre
                case coverImage = "cover_image"
            }
        }
        
        struct Pagination: Codable {
            let page: Int
            let pages: Int
            let perPage: Int
            let items: Int
            
            enum CodingKeys: String, CodingKey {
                case page, pages, items
                case perPage = "per_page"
            }
        }
    }
    
    private struct ReleaseResponse: Codable {
        let id: Int
        let title: String
        let artists: [Artist]?
        let year: Int?
        let labels: [Label]?
        let genres: [String]?
        let images: [Image]?
        let lowestPrice: Double?
        
        struct Artist: Codable {
            let name: String
        }
        
        struct Label: Codable {
            let name: String
            let catno: String?
        }
        
        struct Image: Codable {
            let uri: String
            let type: String
        }
        
        enum CodingKeys: String, CodingKey {
            case id, title, artists, year, labels, genres, images
            case lowestPrice = "lowest_price"
        }
    }
    
    // MARK: - Singleton
    
    static let shared = DiscogsService()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Search for vinyl releases matching extracted data
    /// - Parameter extractedData: The data extracted from the vinyl image
    /// - Returns: Array of DiscogsMatch sorted by match score (highest first)
    /// - Throws: DiscogsError if search fails
    func searchReleases(for extractedData: ExtractedData) async throws -> [DiscogsMatch] {
        // Validate personal token
        guard let personalToken = KeychainService.shared.discogsPersonalToken else {
            throw DiscogsError.noPersonalToken
        }
        
        // Build search query from extracted data
        let searchQuery = buildSearchQuery(from: extractedData)
        
        guard !searchQuery.isEmpty else {
            throw DiscogsError.noMatches
        }
        
        // Perform search with rate limiting
        let searchResults = try await performSearchWithRetry(
            query: searchQuery,
            personalToken: personalToken
        )
        
        guard !searchResults.isEmpty else {
            throw DiscogsError.noMatches
        }
        
        // Convert search results to DiscogsMatch with scoring
        let matches = searchResults.compactMap { result -> DiscogsMatch? in
            guard result.type == "release" || result.type == "master" else {
                return nil
            }
            
            let matchScore = calculateMatchScore(
                result: result,
                extractedData: extractedData
            )
            
            return DiscogsMatch(
                releaseId: result.id,
                title: result.title,
                artist: extractArtistFromTitle(result.title),
                year: Int(result.year ?? ""),
                label: result.label?.first,
                catalogNumber: result.catno,
                matchScore: matchScore,
                imageUrl: URL(string: result.coverImage ?? ""),
                genres: result.genre ?? [],
                lowestPrice: nil, // Will be fetched separately if needed
                medianPrice: nil  // Will be fetched separately if needed
            )
        }
        
        // Sort by match score (highest first) and return top results
        return matches
            .sorted { $0.matchScore > $1.matchScore }
            .prefix(5)
            .map { $0 }
    }
    
    /// Fetch detailed release information including pricing
    /// - Parameter releaseId: The Discogs release ID
    /// - Returns: Updated DiscogsMatch with detailed information
    /// - Throws: DiscogsError if fetch fails
    private func fetchReleaseDetails(releaseId: Int) async throws -> ReleaseResponse {
        guard let personalToken = KeychainService.shared.discogsPersonalToken else {
            throw DiscogsError.noPersonalToken
        }
        
        // Apply rate limiting
        await applyRateLimit()
        
        // Build URL
        guard let url = URL(string: "\(baseURL)\(releaseEndpoint)/\(releaseId)") else {
            throw DiscogsError.invalidURL
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.setValue("Discogs token=\(personalToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FlipSideApp/1.0", forHTTPHeaderField: "User-Agent")
        
        // Execute request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Validate response
        try validateHTTPResponse(response)
        
        // Parse response
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ReleaseResponse.self, from: data)
        } catch {
            throw DiscogsError.parsingError("Failed to decode release details: \(error.localizedDescription)")
        }
    }
    
    /// Generate Discogs release page URL
    /// - Parameter releaseId: The Discogs release ID
    /// - Returns: URL to the Discogs release page
    func generateReleaseURL(releaseId: Int) -> URL? {
        return URL(string: "https://www.discogs.com/release/\(releaseId)")
    }
    
    // MARK: - Private Methods
    
    /// Perform search with retry logic for rate limiting
    private func performSearchWithRetry(
        query: String,
        personalToken: String
    ) async throws -> [SearchResponse.SearchResult] {
        for attempt in 0..<maxRetries {
            do {
                return try await performSearch(
                    query: query,
                    personalToken: personalToken
                )
            } catch DiscogsError.rateLimitExceeded {
                // For rate limits, use exponential backoff
                if attempt < maxRetries - 1 {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            } catch {
                // For other errors, rethrow immediately
                throw error
            }
        }
        
        throw DiscogsError.retryLimitExceeded
    }
    
    /// Perform a single search attempt
    private func performSearch(
        query: String,
        personalToken: String
    ) async throws -> [SearchResponse.SearchResult] {
        // Apply rate limiting
        await applyRateLimit()
        
        // Build URL with query parameters
        var components = URLComponents(string: "\(baseURL)\(searchEndpoint)")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "format", value: "vinyl"),
            URLQueryItem(name: "per_page", value: "\(maxResultsPerSearch)")
        ]
        
        guard let url = components?.url else {
            throw DiscogsError.invalidURL
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.setValue("Discogs token=\(personalToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FlipSideApp/1.0", forHTTPHeaderField: "User-Agent")
        
        // Execute request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Validate response
        try validateHTTPResponse(response)
        
        // Parse response
        let decoder = JSONDecoder()
        do {
            let searchResponse = try decoder.decode(SearchResponse.self, from: data)
            return searchResponse.results
        } catch {
            throw DiscogsError.parsingError("Failed to decode search results: \(error.localizedDescription)")
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
    
    /// Build search query string from extracted data
    private func buildSearchQuery(from extractedData: ExtractedData) -> String {
        var queryParts: [String] = []
        
        // Prioritize artist and album as they're most important
        if let artist = extractedData.artist, !artist.isEmpty {
            queryParts.append(artist)
        }
        
        if let album = extractedData.album, !album.isEmpty {
            queryParts.append(album)
        }
        
        // Add catalog number if available (very specific identifier)
        if let catno = extractedData.catalogNumber, !catno.isEmpty {
            queryParts.append(catno)
        }
        
        // Add label if no artist/album found
        if queryParts.isEmpty, let label = extractedData.label, !label.isEmpty {
            queryParts.append(label)
        }
        
        return queryParts.joined(separator: " ")
    }
    
    /// Calculate match score between search result and extracted data
    private func calculateMatchScore(
        result: SearchResponse.SearchResult,
        extractedData: ExtractedData
    ) -> Double {
        var score: Double = 0.0
        let totalWeight: Double = 1.0 // Sum of all weights (0.30 + 0.30 + 0.25 + 0.10 + 0.05)
        
        // Artist matching (weight: 30%)
        let artistWeight = 0.30
        if let extractedArtist = extractedData.artist {
            let resultArtist = extractArtistFromTitle(result.title)
            let artistSimilarity = stringSimilarity(extractedArtist, resultArtist)
            score += artistSimilarity * artistWeight
        }
        
        // Album matching (weight: 30%)
        let albumWeight = 0.30
        if let extractedAlbum = extractedData.album {
            let albumSimilarity = stringSimilarity(extractedAlbum, result.title)
            score += albumSimilarity * albumWeight
        }
        
        // Catalog number matching (weight: 25%) - highly specific
        let catnoWeight = 0.25
        if let extractedCatno = extractedData.catalogNumber,
           let resultCatno = result.catno {
            let catnoSimilarity = stringSimilarity(extractedCatno, resultCatno)
            score += catnoSimilarity * catnoWeight
        }
        
        // Label matching (weight: 10%)
        let labelWeight = 0.10
        if let extractedLabel = extractedData.label,
           let resultLabels = result.label,
           !resultLabels.isEmpty {
            let labelSimilarities = resultLabels.map { stringSimilarity(extractedLabel, $0) }
            let maxLabelSimilarity = labelSimilarities.max() ?? 0.0
            score += maxLabelSimilarity * labelWeight
        }
        
        // Year matching (weight: 5%) - bonus points for exact match
        let yearWeight = 0.05
        if let extractedYear = extractedData.year,
           let resultYear = result.year,
           let resultYearInt = Int(resultYear) {
            if extractedYear == resultYearInt {
                score += 1.0 * yearWeight
            } else if abs(extractedYear - resultYearInt) <= 2 {
                // Close year match gets partial credit
                score += 0.5 * yearWeight
            }
        }
        
        // Normalize score
        return score / totalWeight
    }
    
    /// Calculate string similarity using Levenshtein distance (normalized)
    private func stringSimilarity(_ str1: String, _ str2: String) -> Double {
        let s1 = str1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let s2 = str2.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for exact match
        if s1 == s2 {
            return 1.0
        }
        
        // Check if one contains the other
        if s1.contains(s2) || s2.contains(s1) {
            return 0.8
        }
        
        // Calculate Levenshtein distance
        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)
        
        guard maxLength > 0 else {
            return 0.0
        }
        
        // Convert distance to similarity (0.0 to 1.0)
        return 1.0 - (Double(distance) / Double(maxLength))
    }
    
    /// Calculate Levenshtein distance between two strings
    private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let s1 = Array(str1)
        let s2 = Array(str2)
        
        var matrix = [[Int]](
            repeating: [Int](repeating: 0, count: s2.count + 1),
            count: s1.count + 1
        )
        
        // Initialize first row and column
        for i in 0...s1.count {
            matrix[i][0] = i
        }
        for j in 0...s2.count {
            matrix[0][j] = j
        }
        
        // Fill matrix
        for i in 1...s1.count {
            for j in 1...s2.count {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        return matrix[s1.count][s2.count]
    }
    
    /// Extract artist name from Discogs title (format: "Artist - Album")
    private func extractArtistFromTitle(_ title: String) -> String {
        let components = title.components(separatedBy: " - ")
        return components.first?.trimmingCharacters(in: .whitespaces) ?? title
    }
    
    /// Validate HTTP response status code
    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscogsError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return
            
        case 401:
            throw DiscogsError.apiError(
                statusCode: 401,
                message: "Invalid personal access token"
            )
            
        case 429:
            throw DiscogsError.rateLimitExceeded
            
        case 404:
            throw DiscogsError.noMatches
            
        case 500...599:
            throw DiscogsError.apiError(
                statusCode: httpResponse.statusCode,
                message: "Discogs server error"
            )
            
        default:
            throw DiscogsError.apiError(
                statusCode: httpResponse.statusCode,
                message: "Unexpected response status"
            )
        }
    }
}

// MARK: - Convenience Extensions

extension DiscogsService {
    
    /// Search and fetch detailed information for matches
    /// - Parameter extractedData: The data extracted from the vinyl image
    /// - Returns: Array of DiscogsMatch with detailed information
    func searchAndFetchDetails(for extractedData: ExtractedData) async throws -> [DiscogsMatch] {
        // First get basic matches
        var matches = try await searchReleases(for: extractedData)
        
        // Fetch details for top 3 matches only (to minimize API calls)
        let topMatches = Array(matches.prefix(3))
        
        for (index, match) in topMatches.enumerated() {
            do {
                let details = try await fetchReleaseDetails(releaseId: match.releaseId)
                
                // Update match with detailed information
                matches[index] = DiscogsMatch(
                    releaseId: match.releaseId,
                    title: details.title,
                    artist: details.artists?.first?.name ?? match.artist,
                    year: details.year ?? match.year,
                    label: details.labels?.first?.name ?? match.label,
                    catalogNumber: details.labels?.first?.catno ?? match.catalogNumber,
                    matchScore: match.matchScore,
                    imageUrl: details.images?.first.flatMap { URL(string: $0.uri) } ?? match.imageUrl,
                    genres: details.genres ?? match.genres,
                    lowestPrice: details.lowestPrice.map { Decimal($0) },
                    medianPrice: nil // Median price requires marketplace stats endpoint
                )
            } catch {
                // If fetching details fails, keep the basic match
                print("Failed to fetch details for release \(match.releaseId): \(error)")
                continue
            }
        }
        
        return matches
    }
}
