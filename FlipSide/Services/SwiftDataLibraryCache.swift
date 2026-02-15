import Foundation
import SwiftData

final class SwiftDataLibraryCache {
    static let shared = SwiftDataLibraryCache()

    private var incrementalSeenKeys: [String: Set<String>] = [:]
    private let incrementalQueue = DispatchQueue(label: "com.flipside.librarycache.incremental")

    private init() {}

    func loadEntries(listType: LibraryListType, in modelContext: ModelContext) throws -> [LibraryEntry] {
        let listTypeRaw = listType.rawValue
        var descriptor = FetchDescriptor<LibraryEntry>(
            predicate: #Predicate { entry in
                entry.listTypeRaw == listTypeRaw
            }
        )
        descriptor.sortBy = [
            SortDescriptor(\LibraryEntry.dateAdded, order: .reverse),
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
                entry.country = item.country
                entry.formatSummary = item.formatSummary
                entry.label = item.label
                entry.catalogNumber = item.catalogNumber
                entry.discogsListItemID = item.discogsListItemID
                entry.position = item.position
                entry.dateAdded = item.dateAdded
                entry.updatedAt = updatedAt
            } else {
                let entry = LibraryEntry(
                    releaseId: item.releaseId,
                    title: item.title,
                    artist: item.artist,
                    imageURLString: item.imageURLString,
                    year: item.year,
                    country: item.country,
                    formatSummary: item.formatSummary,
                    label: item.label,
                    catalogNumber: item.catalogNumber,
                    listType: listType,
                    discogsListItemID: item.discogsListItemID,
                    position: item.position,
                    dateAdded: item.dateAdded,
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

    func beginIncrementalSync(listType: LibraryListType, syncId: UUID, in _: ModelContext) {
        let key = sessionKey(listType: listType, syncId: syncId)
        incrementalQueue.sync {
            incrementalSeenKeys[key] = Set<String>()
        }
    }

    func upsertPage(
        items: [LibraryRemoteItem],
        listType: LibraryListType,
        syncId: UUID,
        updatedAt: Date,
        in modelContext: ModelContext
    ) throws {
        guard !items.isEmpty else {
            return
        }

        let existing = try loadEntries(listType: listType, in: modelContext)
        var existingByKey: [String: LibraryEntry] = [:]
        existing.forEach { entry in
            existingByKey[entryKey(releaseId: entry.releaseId, listType: listType, discogsListItemID: entry.discogsListItemID)] = entry
        }

        var pageKeys = Set<String>()

        for item in items {
            let key = entryKey(releaseId: item.releaseId, listType: listType, discogsListItemID: item.discogsListItemID)
            pageKeys.insert(key)

            if let entry = existingByKey[key] {
                entry.title = item.title
                entry.artist = item.artist
                entry.imageURLString = item.imageURLString
                entry.year = item.year
                entry.country = item.country
                entry.formatSummary = item.formatSummary
                entry.label = item.label
                entry.catalogNumber = item.catalogNumber
                entry.discogsListItemID = item.discogsListItemID
                entry.position = item.position
                entry.dateAdded = item.dateAdded
                entry.updatedAt = updatedAt
            } else {
                let entry = LibraryEntry(
                    releaseId: item.releaseId,
                    title: item.title,
                    artist: item.artist,
                    imageURLString: item.imageURLString,
                    year: item.year,
                    country: item.country,
                    formatSummary: item.formatSummary,
                    label: item.label,
                    catalogNumber: item.catalogNumber,
                    listType: listType,
                    discogsListItemID: item.discogsListItemID,
                    position: item.position,
                    dateAdded: item.dateAdded,
                    updatedAt: updatedAt
                )
                modelContext.insert(entry)
            }
        }

        let key = sessionKey(listType: listType, syncId: syncId)
        incrementalQueue.sync {
            var seen = incrementalSeenKeys[key] ?? Set<String>()
            seen.formUnion(pageKeys)
            incrementalSeenKeys[key] = seen
        }

        try modelContext.save()
    }

    func finalizeIncrementalSync(
        listType: LibraryListType,
        syncId: UUID,
        updatedAt: Date,
        in modelContext: ModelContext
    ) throws {
        let key = sessionKey(listType: listType, syncId: syncId)
        let seenKeys = incrementalQueue.sync {
            incrementalSeenKeys[key] ?? Set<String>()
        }

        let existing = try loadEntries(listType: listType, in: modelContext)
        for entry in existing {
            let entryKey = entryKey(releaseId: entry.releaseId, listType: listType, discogsListItemID: entry.discogsListItemID)
            if !seenKeys.contains(entryKey) {
                modelContext.delete(entry)
            }
        }

        try updateLastRefreshDate(updatedAt, for: listType, in: modelContext)
        try modelContext.save()

        _ = incrementalQueue.sync {
            incrementalSeenKeys.removeValue(forKey: key)
        }
    }

    func failIncrementalSync(listType: LibraryListType, syncId: UUID, in _: ModelContext) {
        let key = sessionKey(listType: listType, syncId: syncId)
        _ = incrementalQueue.sync {
            incrementalSeenKeys.removeValue(forKey: key)
        }
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

    func clearLibraryData(in modelContext: ModelContext) throws {
        let entries = try modelContext.fetch(FetchDescriptor<LibraryEntry>())
        let syncStates = try modelContext.fetch(FetchDescriptor<LibrarySyncState>())

        entries.forEach { modelContext.delete($0) }
        syncStates.forEach { modelContext.delete($0) }

        try modelContext.save()
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

    private func sessionKey(listType: LibraryListType, syncId: UUID) -> String {
        "\(listType.rawValue)-\(syncId.uuidString)"
    }

    private func entryKey(releaseId: Int, listType: LibraryListType, discogsListItemID: Int?) -> String {
        let itemIdComponent = discogsListItemID.map(String.init) ?? "none"
        return "\(listType.rawValue)-\(releaseId)-\(itemIdComponent)"
    }
}
