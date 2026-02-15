import Foundation
import SwiftData

@Model
final class LibraryEntry {
    var id: UUID
    var releaseId: Int
    var title: String
    var artist: String
    var imageURLString: String?
    var year: Int?
    var label: String?
    var catalogNumber: String?
    var listTypeRaw: String
    var discogsListItemID: Int?
    var position: Int?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        releaseId: Int,
        title: String,
        artist: String,
        imageURLString: String? = nil,
        year: Int? = nil,
        label: String? = nil,
        catalogNumber: String? = nil,
        listType: LibraryListType,
        discogsListItemID: Int? = nil,
        position: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.releaseId = releaseId
        self.title = title
        self.artist = artist
        self.imageURLString = imageURLString
        self.year = year
        self.label = label
        self.catalogNumber = catalogNumber
        self.listTypeRaw = listType.rawValue
        self.discogsListItemID = discogsListItemID
        self.position = position
        self.updatedAt = updatedAt
    }

    var listType: LibraryListType {
        get { LibraryListType(rawValue: listTypeRaw) ?? .collection }
        set { listTypeRaw = newValue.rawValue }
    }
}

@Model
final class LibrarySyncState {
    var id: UUID
    var listTypeRaw: String
    var lastRefreshedAt: Date?

    init(id: UUID = UUID(), listType: LibraryListType, lastRefreshedAt: Date? = nil) {
        self.id = id
        self.listTypeRaw = listType.rawValue
        self.lastRefreshedAt = lastRefreshedAt
    }

    var listType: LibraryListType {
        get { LibraryListType(rawValue: listTypeRaw) ?? .collection }
        set { listTypeRaw = newValue.rawValue }
    }
}

enum LibraryListType: String, Codable, CaseIterable {
    case collection
    case wantlist

    var title: String {
        switch self {
        case .collection:
            return "My Collection"
        case .wantlist:
            return "My Wantlist"
        }
    }
}

extension LibraryEntry {
    func toDiscogsMatch() -> DiscogsMatch {
        DiscogsMatch(
            releaseId: releaseId,
            title: title,
            artist: artist,
            year: year,
            released: nil,
            country: nil,
            label: label,
            catalogNumber: catalogNumber,
            matchScore: 1.0,
            imageUrl: imageURLString.flatMap(URL.init(string:)),
            thumbnailUrl: imageURLString.flatMap(URL.init(string:)),
            genres: [],
            styles: [],
            formats: [],
            tracklist: [],
            identifiers: [],
            conditionPrices: nil,
            numForSale: nil,
            inWantlist: nil,
            inCollection: nil,
            notes: nil,
            dataQuality: nil,
            masterId: nil,
            uri: nil,
            resourceUrl: nil,
            videos: []
        )
    }
}
