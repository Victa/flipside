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
    private let marketplaceEndpoint = "/marketplace/price_suggestions"
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0
    private let maxResultsPerSearch = 10
    
    // Rate limiting configuration
    private let rateLimitDelay: TimeInterval = 0.2 // 60 requests/minute = 1 per second (using 0.2s for better UX)
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
        let released: String?
        let country: String?
        let labels: [Label]?
        let genres: [String]?
        let styles: [String]?
        let images: [Image]?
        let thumb: String?
        let formats: [Format]?
        let tracklist: [Track]?
        let identifiers: [Identifier]?
        let videos: [Video]?
        let lowestPrice: Double?
        let numForSale: Int?
        let community: Community?
        let notes: String?
        let dataQuality: String?
        let masterId: Int?
        let uri: String?
        let resourceUrl: String?
        
        struct Artist: Codable {
            let name: String
            let anv: String? // Artist name variation
            let join: String? // Joining word (e.g., "feat.")
            let role: String?
        }
        
        struct Label: Codable {
            let name: String
            let catno: String?
            let entityType: String?
            let entityTypeName: String?
            
            enum CodingKeys: String, CodingKey {
                case name, catno
                case entityType = "entity_type"
                case entityTypeName = "entity_type_name"
            }
        }
        
        struct Image: Codable {
            let uri: String
            let type: String
            let uri150: String?
            let width: Int?
            let height: Int?
            
            enum CodingKeys: String, CodingKey {
                case type, uri, width, height
                case uri150 = "uri150"
            }
        }
        
        struct Format: Codable {
            let name: String
            let qty: String?
            let descriptions: [String]?
            let text: String?
        }
        
        struct Track: Codable {
            let position: String
            let type_: String?
            let title: String
            let duration: String?
            let artists: [Artist]?
            let extraartists: [ExtraArtist]?
            
            enum CodingKeys: String, CodingKey {
                case position, title, duration, artists, extraartists
                case type_ = "type_"
            }
            
            struct ExtraArtist: Codable {
                let name: String
                let anv: String?
                let role: String?
                let tracks: String?
            }
        }
        
        struct Identifier: Codable {
            let type: String
            let value: String
            let description: String?
        }
        
        struct Video: Codable {
            let uri: String
            let title: String
            let description: String?
            let duration: Int?
            let embed: Bool?
        }
        
        struct Community: Codable {
            let have: Int?
            let want: Int?
            let rating: Rating?
            
            struct Rating: Codable {
                let count: Int?
                let average: Double?
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case id, title, artists, year, released, country, labels, genres, styles
            case images, thumb, formats, tracklist, identifiers, videos, notes, uri
            case lowestPrice = "lowest_price"
            case numForSale = "num_for_sale"
            case community
            case dataQuality = "data_quality"
            case masterId = "master_id"
            case resourceUrl = "resource_url"
        }
    }
    
    /// Price suggestion for a single condition grade
    private struct PriceSuggestion: Codable {
        let currency: String
        let value: Double
    }
    
    /// Parsed pricing from the price suggestions endpoint, mapped to condition grades
    private struct ConditionPricing {
        let veryGood: Double?       // VG
        let veryGoodPlus: Double?   // VG+
        let nearMint: Double?       // NM or M-
        let mint: Double?           // M
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
        var searchResults = try await performSearchWithRetry(
            query: searchQuery,
            personalToken: personalToken
        )
        
        // If no results, try fallback searches with simpler queries
        if searchResults.isEmpty {
            searchResults = try await performFallbackSearches(
                extractedData: extractedData,
                personalToken: personalToken
            )
        }
        
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
                // Basic info
                releaseId: result.id,
                title: result.title,
                artist: extractArtistFromTitle(result.title),
                year: Int(result.year ?? ""),
                released: nil,
                country: nil,
                label: result.label?.first,
                catalogNumber: result.catno,
                matchScore: matchScore,
                
                // Images
                imageUrl: URL(string: result.coverImage ?? ""),
                thumbnailUrl: nil,
                
                // Classification
                genres: result.genre ?? [],
                styles: [],
                
                // Formats
                formats: [],
                
                // Tracklist
                tracklist: [],
                
                // Identifiers
                identifiers: [],
                
                // Pricing
                lowestPrice: nil, // Will be fetched separately if needed
                medianPrice: nil, // Will be fetched separately if needed
                highPrice: nil,   // Will be fetched separately if needed
                
                // Community stats
                numForSale: nil,
                inWantlist: nil,
                inCollection: nil,
                
                // Additional info
                notes: nil,
                dataQuality: nil,
                masterId: nil,
                uri: nil,
                resourceUrl: nil,
                videos: []
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
    
    /// Fetch marketplace price suggestions by condition grade
    /// The Discogs price_suggestions endpoint returns a dictionary keyed by condition names
    /// (e.g., "Mint (M)", "Very Good Plus (VG+)") with {currency, value} for each.
    /// - Parameter releaseId: The Discogs release ID
    /// - Returns: ConditionPricing with prices mapped from condition grades
    /// - Throws: DiscogsError if fetch fails
    private func fetchPriceSuggestions(releaseId: Int) async throws -> ConditionPricing {
        guard let personalToken = KeychainService.shared.discogsPersonalToken else {
            throw DiscogsError.noPersonalToken
        }
        
        // Apply rate limiting
        await applyRateLimit()
        
        // Build URL
        guard let url = URL(string: "\(baseURL)\(marketplaceEndpoint)/\(releaseId)") else {
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
        
        // Parse the response as a dictionary of condition → {currency, value}
        // Example: {"Mint (M)": {"currency": "USD", "value": 43.13}, "Very Good Plus (VG+)": {"currency": "USD", "value": 27.64}, ...}
        let decoder = JSONDecoder()
        do {
            let suggestions = try decoder.decode([String: PriceSuggestion].self, from: data)
            
            // Map condition keys to our structured pricing
            // Keys from Discogs: "Mint (M)", "Near Mint (NM or M-)", "Very Good Plus (VG+)",
            //                     "Very Good (VG)", "Good Plus (G+)", "Good (G)", "Fair (F)", "Poor (P)"
            var vg: Double?
            var vgPlus: Double?
            var nm: Double?
            var mint: Double?
            
            for (condition, suggestion) in suggestions {
                let key = condition.lowercased()
                if key.contains("near mint") {
                    nm = suggestion.value
                } else if key.contains("very good plus") || key.contains("vg+") {
                    vgPlus = suggestion.value
                } else if key.contains("very good") {
                    vg = suggestion.value
                } else if key.hasPrefix("mint") || key == "mint (m)" {
                    mint = suggestion.value
                }
            }
            
            return ConditionPricing(
                veryGood: vg,
                veryGoodPlus: vgPlus,
                nearMint: nm,
                mint: mint
            )
        } catch {
            throw DiscogsError.parsingError("Failed to decode price suggestions: \(error.localizedDescription)")
        }
    }
    
    /// Generate Discogs release page URL
    /// - Parameter releaseId: The Discogs release ID
    /// - Returns: URL to the Discogs release page
    func generateReleaseURL(releaseId: Int) -> URL? {
        return URL(string: "https://www.discogs.com/release/\(releaseId)")
    }
    
    /// Fetch complete release details including pricing for a single release
    /// - Parameter releaseId: The Discogs release ID
    /// - Returns: Complete DiscogsMatch with all details and pricing
    /// - Throws: DiscogsError if fetch fails
    func fetchCompleteReleaseDetails(releaseId: Int) async throws -> DiscogsMatch {
        // Fetch release details
        let details = try await fetchReleaseDetails(releaseId: releaseId)
        
        // Fetch price suggestions (optional)
        var priceSuggestions: ConditionPricing?
        do {
            priceSuggestions = try await fetchPriceSuggestions(releaseId: releaseId)
        } catch {
            // Price suggestions are optional - continue if they fail
            print("Price suggestions unavailable for release \(releaseId): \(error)")
        }
        
        // Build complete DiscogsMatch
        return DiscogsMatch(
            // Basic info
            releaseId: releaseId,
            title: details.title,
            artist: details.artists?.first?.name ?? "",
            year: details.year,
            released: details.released,
            country: details.country,
            label: details.labels?.first?.name,
            catalogNumber: details.labels?.first?.catno,
            matchScore: 1.0, // User-selected match
            
            // Images
            imageUrl: details.images?.first.flatMap { URL(string: $0.uri) },
            thumbnailUrl: details.thumb.flatMap { URL(string: $0) },
            
            // Classification
            genres: details.genres ?? [],
            styles: details.styles ?? [],
            
            // Formats
            formats: details.formats?.map { format in
                DiscogsMatch.Format(
                    name: format.name,
                    qty: format.qty,
                    descriptions: format.descriptions,
                    text: format.text
                )
            } ?? [],
            
            // Tracklist
            tracklist: details.tracklist?.map { track in
                DiscogsMatch.TracklistItem(
                    position: track.position,
                    title: track.title,
                    duration: track.duration,
                    artists: track.artists?.map { artist in
                        DiscogsMatch.TracklistItem.TrackArtist(
                            name: artist.name,
                            role: artist.role
                        )
                    },
                    extraartists: track.extraartists?.map { artist in
                        DiscogsMatch.TracklistItem.TrackArtist(
                            name: artist.name,
                            role: artist.role
                        )
                    }
                )
            } ?? [],
            
            // Identifiers
            identifiers: details.identifiers?.map { id in
                DiscogsMatch.Identifier(
                    type: id.type,
                    value: id.value,
                    description: id.description
                )
            } ?? [],
            
            // Pricing - use condition-based price suggestions:
            //   VG (Very Good) → low price, VG+ → median, NM (Near Mint) → high
            // Falls back to release endpoint's lowest_price if no suggestions available
            lowestPrice: priceSuggestions?.veryGood.map { Decimal($0) } ?? details.lowestPrice.map { Decimal($0) },
            medianPrice: priceSuggestions?.veryGoodPlus.map { Decimal($0) },
            highPrice: priceSuggestions?.nearMint.map { Decimal($0) },
            
            // Community stats
            numForSale: details.numForSale,
            inWantlist: details.community?.want,
            inCollection: details.community?.have,
            
            // Additional info
            notes: details.notes,
            dataQuality: details.dataQuality,
            masterId: details.masterId,
            uri: details.uri,
            resourceUrl: details.resourceUrl,
            videos: details.videos?.map { video in
                DiscogsMatch.Video(
                    uri: video.uri,
                    title: video.title,
                    description: video.description,
                    duration: video.duration
                )
            } ?? []
        )
    }
    
    // MARK: - Private Methods
    
    /// Perform fallback searches with simpler queries when primary search fails
    private func performFallbackSearches(
        extractedData: ExtractedData,
        personalToken: String
    ) async throws -> [SearchResponse.SearchResult] {
        // Fallback 1: Artist + First track title (good for singles/EPs)
        if let artist = extractedData.artist, !artist.isEmpty,
           let tracks = extractedData.tracks, !tracks.isEmpty {
            let firstTrack = tracks[0].title
            if !firstTrack.isEmpty {
                let query1 = "\(artist) \(firstTrack)"
                if let results = try? await performSearchWithRetry(query: query1, personalToken: personalToken),
                   !results.isEmpty {
                    return results
                }
            }
        }
        
        // Fallback 2: Artist + Album only
        if let artist = extractedData.artist, !artist.isEmpty,
           let album = extractedData.album, !album.isEmpty {
            let query2 = "\(artist) \(album)"
            if let results = try? await performSearchWithRetry(query: query2, personalToken: personalToken),
               !results.isEmpty {
                return results
            }
        }
        
        // No fallback strategies worked
        return []
    }
    
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
            // Note: Not filtering by format=vinyl to include lathe cuts and other formats
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
    
    /// Build primary search query (catalog number only - most specific)
    private func buildSearchQuery(from extractedData: ExtractedData) -> String {
        // Primary strategy: Catalog number only (most specific identifier)
        if let catno = extractedData.catalogNumber, !catno.isEmpty {
            return catno
        }
        
        // Fallback to artist if no catalog number
        if let artist = extractedData.artist, !artist.isEmpty {
            return artist
        }
        
        // Last resort: any available field
        if let album = extractedData.album, !album.isEmpty {
            return album
        }
        
        if let label = extractedData.label, !label.isEmpty {
            return label
        }
        
        return ""
    }
    
    /// Calculate match score between search result and extracted data
    private func calculateMatchScore(
        result: SearchResponse.SearchResult,
        extractedData: ExtractedData
    ) -> Double {
        var score: Double = 0.0
        let totalWeight: Double = 1.0 // Sum of all weights (0.30 + 0.30 + 0.25 + 0.10 + 0.05)
        
        // Check for exact catalog number match first - this is a unique identifier
        var hasCatalogExactMatch = false
        if let extractedCatno = extractedData.catalogNumber,
           let resultCatno = result.catno {
            let catnoSimilarity = stringSimilarity(extractedCatno, resultCatno)
            if catnoSimilarity == 1.0 {
                hasCatalogExactMatch = true
            }
        }
        
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
        var normalizedScore = score / totalWeight
        
        // CATALOG NUMBER EXACT MATCH BONUS
        // If catalog number matches exactly, set a high minimum confidence
        // because catalog numbers are unique identifiers
        if hasCatalogExactMatch {
            normalizedScore = max(normalizedScore, 0.92) // Ensure at least 92% confidence
        }
        
        return normalizedScore
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
                
                // Fetch price suggestions by condition grade (VG, VG+, NM, M)
                var priceSuggestions: ConditionPricing?
                do {
                    priceSuggestions = try await fetchPriceSuggestions(releaseId: match.releaseId)
                } catch {
                    // Price suggestions are optional - continue if they fail
                    // (e.g., user may not have a seller profile, or release has no sales data)
                    print("Failed to fetch price suggestions for release \(match.releaseId): \(error)")
                }
                
                // Update match with ALL detailed information
                matches[index] = DiscogsMatch(
                    // Basic info
                    releaseId: match.releaseId,
                    title: details.title,
                    artist: details.artists?.first?.name ?? match.artist,
                    year: details.year ?? match.year,
                    released: details.released,
                    country: details.country,
                    label: details.labels?.first?.name ?? match.label,
                    catalogNumber: details.labels?.first?.catno ?? match.catalogNumber,
                    matchScore: match.matchScore,
                    
                    // Images
                    imageUrl: details.images?.first.flatMap { URL(string: $0.uri) } ?? match.imageUrl,
                    thumbnailUrl: details.thumb.flatMap { URL(string: $0) },
                    
                    // Classification
                    genres: details.genres ?? match.genres,
                    styles: details.styles ?? [],
                    
                    // Formats
                    formats: details.formats?.map { format in
                        DiscogsMatch.Format(
                            name: format.name,
                            qty: format.qty,
                            descriptions: format.descriptions,
                            text: format.text
                        )
                    } ?? [],
                    
                    // Tracklist
                    tracklist: details.tracklist?.map { track in
                        DiscogsMatch.TracklistItem(
                            position: track.position,
                            title: track.title,
                            duration: track.duration,
                            artists: track.artists?.map { artist in
                                DiscogsMatch.TracklistItem.TrackArtist(
                                    name: artist.name,
                                    role: artist.role
                                )
                            },
                            extraartists: track.extraartists?.map { artist in
                                DiscogsMatch.TracklistItem.TrackArtist(
                                    name: artist.name,
                                    role: artist.role
                                )
                            }
                        )
                    } ?? [],
                    
                    // Identifiers
                    identifiers: details.identifiers?.map { id in
                        DiscogsMatch.Identifier(
                            type: id.type,
                            value: id.value,
                            description: id.description
                        )
                    } ?? [],
                    
                    // Pricing - use condition-based price suggestions:
                    //   VG (Very Good) → low price, VG+ → median, NM (Near Mint) → high
                    // Falls back to release endpoint's lowest_price if no suggestions available
                    lowestPrice: priceSuggestions?.veryGood.map { Decimal($0) } ?? details.lowestPrice.map { Decimal($0) },
                    medianPrice: priceSuggestions?.veryGoodPlus.map { Decimal($0) },
                    highPrice: priceSuggestions?.nearMint.map { Decimal($0) },
                    
                    // Community stats
                    numForSale: details.numForSale,
                    inWantlist: details.community?.want,
                    inCollection: details.community?.have,
                    
                    // Additional info
                    notes: details.notes,
                    dataQuality: details.dataQuality,
                    masterId: details.masterId,
                    uri: details.uri,
                    resourceUrl: details.resourceUrl,
                    videos: details.videos?.map { video in
                        DiscogsMatch.Video(
                            uri: video.uri,
                            title: video.title,
                            description: video.description,
                            duration: video.duration
                        )
                    } ?? []
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
