import Foundation
import SwiftData

@MainActor
final class DetailViewModel: ObservableObject {
    @Published private(set) var completeMatch: DiscogsMatch?
    @Published private(set) var isLoadingDetails = false
    @Published private(set) var loadError: String?

    private var cachedVideoSourceKey: String?
    private var cachedVideos: [DiscogsMatch.Video] = []
    private let detailsCacheTTL: TimeInterval = 24 * 60 * 60
    private let priceCacheTTL: TimeInterval = 6 * 60 * 60

    static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    var displayMatch: DiscogsMatch? {
        completeMatch
    }

    func loadCompleteDetailsIfNeeded(
        from match: DiscogsMatch,
        scanId: UUID?,
        networkConnected: Bool,
        modelContext: ModelContext
    ) async {
        let alreadyComplete = !match.tracklist.isEmpty && !match.formats.isEmpty
        guard !alreadyComplete else {
            completeMatch = match
            return
        }

        let now = Date()
        var hasCachedValue = false
        var detailsFresh = false
        var pricesFresh = false

        if let cacheEntry = loadReleaseCacheEntry(releaseId: match.releaseId, in: modelContext),
           let cachedMatch = decodeCachedMatch(from: cacheEntry) {
            completeMatch = cachedMatch
            hasCachedValue = true
            detailsFresh = now.timeIntervalSince(cacheEntry.detailsFetchedAt) <= detailsCacheTTL
            if let priceFetchedAt = cacheEntry.priceFetchedAt {
                pricesFresh = now.timeIntervalSince(priceFetchedAt) <= priceCacheTTL
            }
            updateCachedScan(with: cachedMatch, scanId: scanId, in: modelContext)
        }

        if hasCachedValue && detailsFresh && pricesFresh {
            return
        }

        guard networkConnected else {
            if !hasCachedValue {
                completeMatch = match
            }
            return
        }

        isLoadingDetails = true
        loadError = nil
        let interval = PerformanceMetrics.begin(.resultsToDetailFirstPaint)

        do {
            let complete = try await DiscogsService.shared.fetchCompleteReleaseDetails(releaseId: match.releaseId)
            completeMatch = complete
            isLoadingDetails = false
            updateCachedScan(with: complete, scanId: scanId, in: modelContext)
            upsertReleaseCache(with: complete, fetchedAt: Date(), in: modelContext)
        } catch {
            loadError = error.localizedDescription
            isLoadingDetails = false
            if !hasCachedValue {
                completeMatch = match
            }
        }

        PerformanceMetrics.end(.resultsToDetailFirstPaint, interval)
    }

    func displayVideos(for match: DiscogsMatch) -> [DiscogsMatch.Video] {
        let key = "\(match.releaseId)-\(match.videos.count)-\(match.videos.map(\.uri).joined(separator: "|"))"
        if key == cachedVideoSourceKey {
            return cachedVideos
        }

        var uniqueVideos: [DiscogsMatch.Video] = []
        var seenKeys = Set<String>()

        for video in match.videos {
            let normalizedURI = video.uri.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedTitle = video.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let dedupeKey: String

            if let youtubeID = youtubeVideoID(from: normalizedURI) {
                dedupeKey = "youtube:\(youtubeID)"
            } else if !normalizedURI.isEmpty {
                dedupeKey = "uri:\(normalizedURI)"
            } else {
                dedupeKey = "title:\(normalizedTitle)|duration:\(video.duration ?? -1)"
            }

            guard !seenKeys.contains(dedupeKey) else { continue }
            seenKeys.insert(dedupeKey)
            uniqueVideos.append(video)
        }

        cachedVideoSourceKey = key
        cachedVideos = uniqueVideos
        return uniqueVideos
    }

    func formatPrice(_ price: Decimal) -> String {
        Self.priceFormatter.string(from: price as NSDecimalNumber) ?? "$\(price)"
    }

    private func updateCachedScan(with completeMatch: DiscogsMatch, scanId: UUID?, in modelContext: ModelContext) {
        guard let scanId else { return }

        let fetchDescriptor = FetchDescriptor<Scan>(
            predicate: #Predicate { $0.id == scanId }
        )

        if let scan = try? modelContext.fetch(fetchDescriptor).first,
           let selectedIndex = scan.selectedMatchIndex,
           selectedIndex < scan.discogsMatches.count {
            scan.discogsMatches[selectedIndex] = completeMatch
            try? modelContext.save()
        }
    }

    private func loadReleaseCacheEntry(releaseId: Int, in modelContext: ModelContext) -> DiscogsReleaseDetailsCacheEntry? {
        var descriptor = FetchDescriptor<DiscogsReleaseDetailsCacheEntry>(
            predicate: #Predicate { $0.releaseId == releaseId }
        )
        descriptor.sortBy = [SortDescriptor(\DiscogsReleaseDetailsCacheEntry.detailsFetchedAt, order: .reverse)]
        return try? modelContext.fetch(descriptor).first
    }

    private func decodeCachedMatch(from cacheEntry: DiscogsReleaseDetailsCacheEntry) -> DiscogsMatch? {
        try? JSONDecoder().decode(DiscogsMatch.self, from: cacheEntry.payloadData)
    }

    private func upsertReleaseCache(with match: DiscogsMatch, fetchedAt: Date, in modelContext: ModelContext) {
        guard let encoded = try? JSONEncoder().encode(match) else { return }

        var descriptor = FetchDescriptor<DiscogsReleaseDetailsCacheEntry>(
            predicate: #Predicate { $0.releaseId == match.releaseId }
        )
        descriptor.sortBy = [SortDescriptor(\DiscogsReleaseDetailsCacheEntry.detailsFetchedAt, order: .reverse)]

        let existing = (try? modelContext.fetch(descriptor)) ?? []

        if let entry = existing.first {
            entry.payloadData = encoded
            entry.detailsFetchedAt = fetchedAt
            entry.priceFetchedAt = (match.conditionPrices?.isEmpty == false) ? fetchedAt : nil

            if existing.count > 1 {
                for duplicate in existing.dropFirst() {
                    modelContext.delete(duplicate)
                }
            }
        } else {
            let entry = DiscogsReleaseDetailsCacheEntry(
                releaseId: match.releaseId,
                payloadData: encoded,
                detailsFetchedAt: fetchedAt,
                priceFetchedAt: (match.conditionPrices?.isEmpty == false) ? fetchedAt : nil
            )
            modelContext.insert(entry)
        }

        try? modelContext.save()
    }

    private func youtubeVideoID(from uri: String) -> String? {
        let trimmedURI = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedURI) else { return nil }
        guard let host = components.host?.lowercased() else { return nil }

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let id = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        }

        let isYouTubeHost = host == "youtube.com"
            || host == "www.youtube.com"
            || host == "m.youtube.com"
            || host == "music.youtube.com"

        guard isYouTubeHost else { return nil }

        let path = components.path
        let lowercasedPath = path.lowercased()

        if lowercasedPath == "/watch" {
            let id = components.queryItems?.first(where: { $0.name.lowercased() == "v" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (id?.isEmpty == false) ? id : nil
        }

        for prefix in ["/embed/", "/shorts/", "/live/", "/v/"] {
            if lowercasedPath.hasPrefix(prefix) {
                let id = String(path.dropFirst(prefix.count)).split(separator: "/").first.map(String.init)
                return (id?.isEmpty == false) ? id : nil
            }
        }

        return nil
    }
}
