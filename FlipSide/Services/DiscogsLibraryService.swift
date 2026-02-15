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

struct LibraryPageChunk {
    let listType: LibraryListType
    let page: Int
    let totalPages: Int
    let itemsReceivedThisPage: Int
    let totalItemsExpected: Int?
}

struct LibrarySyncSummary {
    let listType: LibraryListType
    let pagesFetched: Int
    let totalPages: Int
    let itemsFetched: Int
    let totalItemsExpected: Int?
    let completed: Bool
}

final class DiscogsLibraryService {
    static let shared = DiscogsLibraryService()

    private let baseURL = "https://api.discogs.com"
    private let userAgent = "FlipSideApp/1.0"
    private let max429Retries = 3
    private let rateLimiter = DiscogsRateLimiter.shared

    enum LibraryServiceError: LocalizedError {
        case notConnected
        case missingUsername
        case invalidURL
        case invalidResponse
        case requestFailed(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Discogs account is not connected. Connect in Settings."
            case .missingUsername:
                return "Discogs username is unavailable. Reconnect your Discogs account in Settings."
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
        return try await fetchPaginatedCollectionItems(endpoint: endpoint)
    }

    func fetchWantlist(username: String) async throws -> [LibraryRemoteItem] {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibraryServiceError.missingUsername
        }

        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let endpoint = "/users/\(encoded)/wants"
        return try await fetchPaginatedWantlistItems(endpoint: endpoint)
    }

    func syncCollectionPaged(
        username: String,
        onPage: @escaping @MainActor ([LibraryRemoteItem], LibraryPageChunk) throws -> Void
    ) async throws -> LibrarySyncSummary {
        try await syncListPaged(listType: .collection, username: username, onPage: onPage)
    }

    func syncWantlistPaged(
        username: String,
        onPage: @escaping @MainActor ([LibraryRemoteItem], LibraryPageChunk) throws -> Void
    ) async throws -> LibrarySyncSummary {
        try await syncListPaged(listType: .wantlist, username: username, onPage: onPage)
    }

    func syncListPaged(
        listType: LibraryListType,
        username: String,
        onPage: @escaping @MainActor ([LibraryRemoteItem], LibraryPageChunk) throws -> Void
    ) async throws -> LibrarySyncSummary {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibraryServiceError.missingUsername
        }

        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let endpoint: String
        switch listType {
        case .collection:
            endpoint = "/users/\(encoded)/collection/folders/0/releases"
        case .wantlist:
            endpoint = "/users/\(encoded)/wants"
        }

        var page = 1
        var totalPages = 1
        var totalItemsExpected: Int?
        var itemsFetched = 0

        repeat {
            switch listType {
            case .collection:
                let pageResponse: CollectionResponse = try await request(endpoint: endpoint, page: page)
                let parsedItems = mapCollection(pageResponse, page: page)
                totalPages = max(pageResponse.pagination.pages, 1)
                totalItemsExpected = pageResponse.pagination.items
                itemsFetched += parsedItems.count

                let chunk = LibraryPageChunk(
                    listType: listType,
                    page: page,
                    totalPages: totalPages,
                    itemsReceivedThisPage: parsedItems.count,
                    totalItemsExpected: totalItemsExpected
                )

                try await MainActor.run {
                    try onPage(parsedItems, chunk)
                }
            case .wantlist:
                let pageResponse: WantlistResponse = try await request(endpoint: endpoint, page: page)
                let parsedItems = mapWantlist(pageResponse, page: page)
                totalPages = max(pageResponse.pagination.pages, 1)
                totalItemsExpected = pageResponse.pagination.items
                itemsFetched += parsedItems.count

                let chunk = LibraryPageChunk(
                    listType: listType,
                    page: page,
                    totalPages: totalPages,
                    itemsReceivedThisPage: parsedItems.count,
                    totalItemsExpected: totalItemsExpected
                )

                try await MainActor.run {
                    try onPage(parsedItems, chunk)
                }
            }

            page += 1
        } while page <= totalPages

        return LibrarySyncSummary(
            listType: listType,
            pagesFetched: max(page - 1, 0),
            totalPages: totalPages,
            itemsFetched: itemsFetched,
            totalItemsExpected: totalItemsExpected,
            completed: true
        )
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
        guard DiscogsAuthService.shared.isConnected else {
            throw LibraryServiceError.notConnected
        }

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
        try DiscogsAuthService.shared.authorizeRequest(&request)

        let data: Data
        do {
            (data, _) = try await performRequestWithRetry(request)
        } catch let error as LibraryServiceError {
            throw error
        } catch {
            throw LibraryServiceError.invalidResponse
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

    private func performRequestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 0
        var backoff: UInt64 = 1_000_000_000

        while true {
            await applyRateLimit()
            if let url = request.url {
                PerformanceMetrics.incrementCounter(counterName(for: url))
            }
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LibraryServiceError.invalidResponse
            }

            if (200...299).contains(httpResponse.statusCode) {
                return (data, response)
            }

            if httpResponse.statusCode == 401 {
                try? DiscogsAuthService.shared.disconnect()
                throw LibraryServiceError.notConnected
            }

            if httpResponse.statusCode == 429, attempt < max429Retries {
                let retryAfter = DiscogsRateLimiter.retryAfterSeconds(from: httpResponse)
                await rateLimiter.backoff(attempt: attempt, retryAfter: retryAfter ?? (Double(backoff) / 1_000_000_000))
                backoff *= 2
                attempt += 1
                continue
            }

            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = (body?.isEmpty == false) ? body! : "Request failed. Please try again in a moment."
            throw LibraryServiceError.requestFailed(httpResponse.statusCode, message)
        }
    }

    private func applyRateLimit() async {
        await rateLimiter.acquire()
    }

    private func counterName(for url: URL) -> String {
        let path = url.path
        if path.contains("/collection/folders/0/releases") {
            return "discogs_api_get_collection_pages"
        }
        if path.contains("/wants") {
            return "discogs_api_get_wantlist_pages"
        }
        return "discogs_api_get_library_other"
    }
}
