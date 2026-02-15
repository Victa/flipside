import Foundation

struct LibraryRemoteItem {
    let releaseId: Int
    let title: String
    let artist: String
    let imageURLString: String?
    let year: Int?
    let country: String?
    let formatSummary: String?
    let label: String?
    let catalogNumber: String?
    let discogsListItemID: Int?
    let position: Int?
    let dateAdded: Date?
}

final class DiscogsLibraryService {
    static let shared = DiscogsLibraryService()

    private let baseURL = "https://api.discogs.com"
    private let userAgent = "FlipSideApp/1.0"

    enum LibraryServiceError: LocalizedError {
        case missingUsername
        case invalidURL
        case invalidResponse
        case requestFailed(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingUsername:
                return "Discogs username is required. Add it in Settings."
            case .invalidURL:
                return "Failed to build Discogs API URL."
            case .invalidResponse:
                return "Received an invalid response from Discogs."
            case let .requestFailed(code, message):
                return "Discogs library fetch failed (\(code)): \(message)"
            }
        }
    }

    private init() {}

    func fetchCollection(username: String) async throws -> [LibraryRemoteItem] {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibraryServiceError.missingUsername
        }

        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let endpoint = "/users/\(encoded)/collection/folders/0/releases"
        let items = try await fetchPaginatedCollectionItems(endpoint: endpoint)
        return await enrichItemsWithReleaseMetadata(items)
    }

    func fetchWantlist(username: String) async throws -> [LibraryRemoteItem] {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibraryServiceError.missingUsername
        }

        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let endpoint = "/users/\(encoded)/wants"
        let items = try await fetchPaginatedWantlistItems(endpoint: endpoint)
        return await enrichItemsWithReleaseMetadata(items)
    }

    private func fetchPaginatedCollectionItems(endpoint: String) async throws -> [LibraryRemoteItem] {
        var page = 1
        var totalPages = 1
        var allItems: [LibraryRemoteItem] = []

        repeat {
            let pageResponse: CollectionResponse = try await request(endpoint: endpoint, page: page)
            let parsedItems = mapCollection(pageResponse, page: page)
            allItems.append(contentsOf: parsedItems)
            totalPages = max(pageResponse.pagination.pages, 1)

            page += 1
        } while page <= totalPages

        return allItems
    }

    private func fetchPaginatedWantlistItems(endpoint: String) async throws -> [LibraryRemoteItem] {
        var page = 1
        var totalPages = 1
        var allItems: [LibraryRemoteItem] = []

        repeat {
            let pageResponse: WantlistResponse = try await request(endpoint: endpoint, page: page)
            let parsedItems = mapWantlist(pageResponse, page: page)
            allItems.append(contentsOf: parsedItems)
            totalPages = max(pageResponse.pagination.pages, 1)

            page += 1
        } while page <= totalPages

        return allItems
    }

    private func request<T: Decodable>(endpoint: String, page: Int) async throws -> T {
        var components = URLComponents(string: "\(baseURL)\(endpoint)")
        components?.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: "100")
        ]

        guard let url = components?.url else {
            throw LibraryServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        if let token = KeychainService.shared.discogsPersonalToken,
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LibraryServiceError.requestFailed(httpResponse.statusCode, message)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                if let date = DiscogsLibraryService.dateFormatterWithFractionalSeconds.date(from: value) {
                    return date
                }
                if let date = DiscogsLibraryService.dateFormatter.date(from: value) {
                    return date
                }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(value)")
            }
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LibraryServiceError.invalidResponse
        }
    }

    private func mapCollection(_ response: CollectionResponse, page: Int) -> [LibraryRemoteItem] {
        response.releases.enumerated().map { index, item in
            let basic = item.basicInformation
            let artist = basic.artists?.first?.name ?? "Unknown Artist"
            let label = basic.labels?.first?.name
            let catno = basic.labels?.first?.catno
            let yearValue: Int?
            if let year = basic.year, year != 0 {
                yearValue = year
            } else {
                yearValue = nil
            }
            let position = ((page - 1) * 100) + index

            return LibraryRemoteItem(
                releaseId: basic.id,
                title: basic.title,
                artist: artist,
                imageURLString: basic.coverImage,
                year: yearValue,
                country: basic.country,
                formatSummary: formatSummary(from: basic.formats),
                label: label,
                catalogNumber: catno,
                discogsListItemID: item.instanceID,
                position: position,
                dateAdded: item.dateAdded
            )
        }
    }

    private func mapWantlist(_ response: WantlistResponse, page: Int) -> [LibraryRemoteItem] {
        response.wants.enumerated().map { index, item in
            let basic = item.basicInformation
            let artist = basic.artists?.first?.name ?? "Unknown Artist"
            let label = basic.labels?.first?.name
            let catno = basic.labels?.first?.catno
            let yearValue: Int?
            if let year = basic.year, year != 0 {
                yearValue = year
            } else {
                yearValue = nil
            }
            let position = ((page - 1) * 100) + index

            return LibraryRemoteItem(
                releaseId: basic.id,
                title: basic.title,
                artist: artist,
                imageURLString: basic.coverImage,
                year: yearValue,
                country: basic.country,
                formatSummary: formatSummary(from: basic.formats),
                label: label,
                catalogNumber: catno,
                discogsListItemID: nil,
                position: position,
                dateAdded: item.dateAdded
            )
        }
    }
}

private struct CollectionResponse: Decodable {
    let pagination: Pagination
    let releases: [CollectionItem]

    struct CollectionItem: Decodable {
        let instanceID: Int
        let dateAdded: Date?
        let basicInformation: BasicInformation

        enum CodingKeys: String, CodingKey {
            case instanceID = "instance_id"
            case dateAdded = "date_added"
            case basicInformation = "basic_information"
        }
    }
}

private struct WantlistResponse: Decodable {
    let pagination: Pagination
    let wants: [WantItem]

    struct WantItem: Decodable {
        let id: Int
        let dateAdded: Date?
        let basicInformation: BasicInformation

        enum CodingKeys: String, CodingKey {
            case id
            case dateAdded = "date_added"
            case basicInformation = "basic_information"
        }
    }
}

private struct Pagination: Decodable {
    let page: Int
    let pages: Int
    let items: Int

    enum CodingKeys: String, CodingKey {
        case page
        case pages
        case items
    }
}

private struct BasicInformation: Decodable {
    let id: Int
    let title: String
    let year: Int?
    let country: String?
    let coverImage: String?
    let artists: [Artist]?
    let labels: [Label]?
    let formats: [Format]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case country
        case coverImage = "cover_image"
        case artists
        case labels
        case formats
    }

    struct Artist: Decodable {
        let name: String
    }

    struct Label: Decodable {
        let name: String
        let catno: String?
    }

    struct Format: Decodable {
        let name: String
        let descriptions: [String]?
        let text: String?
    }
}

private struct ReleaseMetadataResponse: Decodable {
    let country: String?
    let formats: [BasicInformation.Format]?
}

extension DiscogsLibraryService {
    static let dateFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func formatSummary(from formats: [BasicInformation.Format]?) -> String? {
        guard let formats, !formats.isEmpty else {
            return nil
        }

        var parts: [String] = []
        var seen = Set<String>()

        for format in formats {
            let candidates = [format.name] + (format.descriptions ?? []) + [format.text]
            for value in candidates {
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !trimmed.isEmpty else { continue }

                let key = trimmed.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    parts.append(trimmed)
                }
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func enrichItemsWithReleaseMetadata(_ items: [LibraryRemoteItem]) async -> [LibraryRemoteItem] {
        var enriched = items

        for index in enriched.indices {
            let needsCountry = (enriched[index].country?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let needsFormat = (enriched[index].formatSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            guard needsCountry || needsFormat else {
                continue
            }

            guard let metadata = try? await fetchReleaseMetadata(releaseId: enriched[index].releaseId) else {
                continue
            }

            let resolvedCountry = needsCountry ? metadata.country : enriched[index].country
            let resolvedFormat = needsFormat
                ? formatSummary(from: metadata.formats) ?? enriched[index].formatSummary
                : enriched[index].formatSummary

            enriched[index] = LibraryRemoteItem(
                releaseId: enriched[index].releaseId,
                title: enriched[index].title,
                artist: enriched[index].artist,
                imageURLString: enriched[index].imageURLString,
                year: enriched[index].year,
                country: resolvedCountry,
                formatSummary: resolvedFormat,
                label: enriched[index].label,
                catalogNumber: enriched[index].catalogNumber,
                discogsListItemID: enriched[index].discogsListItemID,
                position: enriched[index].position,
                dateAdded: enriched[index].dateAdded
            )

            // Discogs applies stricter limits to release endpoints. Keep enrichment gentle.
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        return enriched
    }

    private func fetchReleaseMetadata(releaseId: Int) async throws -> ReleaseMetadataResponse {
        guard let url = URL(string: "\(baseURL)/releases/\(releaseId)") else {
            throw LibraryServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        if let token = KeychainService.shared.discogsPersonalToken,
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        }

        for attempt in 0..<2 {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LibraryServiceError.invalidResponse
            }

            if httpResponse.statusCode == 429, attempt == 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw LibraryServiceError.requestFailed(httpResponse.statusCode, message)
            }

            let decoder = JSONDecoder()
            return try decoder.decode(ReleaseMetadataResponse.self, from: data)
        }

        throw LibraryServiceError.invalidResponse
    }
}
