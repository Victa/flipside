import Foundation
import SwiftData

final class SwiftDataLibraryCache {
    static let shared = SwiftDataLibraryCache()

    private init() {}

    func loadEntries(listType: LibraryListType, in modelContext: ModelContext) throws -> [LibraryEntry] {
        let listTypeRaw = listType.rawValue
        var descriptor = FetchDescriptor<LibraryEntry>(
            predicate: #Predicate { entry in
                entry.listTypeRaw == listTypeRaw
            }
        )
        descriptor.sortBy = [
            SortDescriptor(\LibraryEntry.position, order: .forward),
            SortDescriptor(\LibraryEntry.title, order: .forward)
        ]
        return try modelContext.fetch(descriptor)
    }

    func replaceEntries(
        _ items: [LibraryRemoteItem],
        listType: LibraryListType,
        updatedAt: Date,
        in modelContext: ModelContext
    ) throws {
        let existing = try loadEntries(listType: listType, in: modelContext)

        var existingByKey: [String: LibraryEntry] = [:]
        existing.forEach { entry in
            existingByKey[entryKey(releaseId: entry.releaseId, listType: listType, discogsListItemID: entry.discogsListItemID)] = entry
        }

        var incomingKeys = Set<String>()

        for item in items {
            let key = entryKey(releaseId: item.releaseId, listType: listType, discogsListItemID: item.discogsListItemID)
            incomingKeys.insert(key)

            if let entry = existingByKey[key] {
                entry.title = item.title
                entry.artist = item.artist
                entry.imageURLString = item.imageURLString
                entry.year = item.year
                entry.label = item.label
                entry.catalogNumber = item.catalogNumber
                entry.discogsListItemID = item.discogsListItemID
                entry.position = item.position
                entry.updatedAt = updatedAt
            } else {
                let entry = LibraryEntry(
                    releaseId: item.releaseId,
                    title: item.title,
                    artist: item.artist,
                    imageURLString: item.imageURLString,
                    year: item.year,
                    label: item.label,
                    catalogNumber: item.catalogNumber,
                    listType: listType,
                    discogsListItemID: item.discogsListItemID,
                    position: item.position,
                    updatedAt: updatedAt
                )
                modelContext.insert(entry)
            }
        }

        for entry in existing {
            let key = entryKey(releaseId: entry.releaseId, listType: listType, discogsListItemID: entry.discogsListItemID)
            if !incomingKeys.contains(key) {
                modelContext.delete(entry)
            }
        }

        try updateLastRefreshDate(updatedAt, for: listType, in: modelContext)
        try modelContext.save()
    }

    func lastRefreshDate(listType: LibraryListType, in modelContext: ModelContext) throws -> Date? {
        let listTypeRaw = listType.rawValue
        let descriptor = FetchDescriptor<LibrarySyncState>(
            predicate: #Predicate { state in
                state.listTypeRaw == listTypeRaw
            }
        )

        return try modelContext.fetch(descriptor).first?.lastRefreshedAt
    }

    private func updateLastRefreshDate(
        _ date: Date,
        for listType: LibraryListType,
        in modelContext: ModelContext
    ) throws {
        let listTypeRaw = listType.rawValue
        let descriptor = FetchDescriptor<LibrarySyncState>(
            predicate: #Predicate { state in
                state.listTypeRaw == listTypeRaw
            }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.lastRefreshedAt = date
        } else {
            let state = LibrarySyncState(listType: listType, lastRefreshedAt: date)
            modelContext.insert(state)
        }
    }

    private func entryKey(releaseId: Int, listType: LibraryListType, discogsListItemID: Int?) -> String {
        let itemIdComponent = discogsListItemID.map(String.init) ?? "none"
        return "\(listType.rawValue)-\(releaseId)-\(itemIdComponent)"
    }
}
