import Foundation

struct LibraryRemoteItem {
    let releaseId: Int
    let title: String
    let artist: String
    let imageURLString: String?
    let year: Int?
    let label: String?
    let catalogNumber: String?
    let discogsListItemID: Int?
    let position: Int?
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
            return try JSONDecoder().decode(T.self, from: data)
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
                label: label,
                catalogNumber: catno,
                discogsListItemID: item.instanceID,
                position: position
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
                label: label,
                catalogNumber: catno,
                discogsListItemID: nil,
                position: position
            )
        }
    }
}

private struct CollectionResponse: Decodable {
    let pagination: Pagination
    let releases: [CollectionItem]

    struct CollectionItem: Decodable {
        let instanceID: Int
        let basicInformation: BasicInformation

        enum CodingKeys: String, CodingKey {
            case instanceID = "instance_id"
            case basicInformation = "basic_information"
        }
    }
}

private struct WantlistResponse: Decodable {
    let pagination: Pagination
    let wants: [WantItem]

    struct WantItem: Decodable {
        let id: Int
        let basicInformation: BasicInformation

        enum CodingKeys: String, CodingKey {
            case id
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
    let coverImage: String?
    let artists: [Artist]?
    let labels: [Label]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case coverImage = "cover_image"
        case artists
        case labels
    }

    struct Artist: Decodable {
        let name: String
    }

    struct Label: Decodable {
        let name: String
        let catno: String?
    }
}
