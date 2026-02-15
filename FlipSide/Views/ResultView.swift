//
//  ResultView.swift
//  FlipSide
//
//  Match selection view with horizontal carousel of Discogs matches
//

import SwiftUI

struct ResultView: View {
    @Environment(\.modelContext) private var modelContext

    let image: UIImage
    let extractedData: ExtractedData
    let discogsMatches: [DiscogsMatch]
    let discogsError: String?
    let scanId: UUID?
    let onMatchSelected: (DiscogsMatch, Int) -> Void
    
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var authService = DiscogsAuthService.shared
    private let libraryCache = SwiftDataLibraryCache.shared
    private let libraryFreshInterval: TimeInterval = 15 * 60
    
    // Collection status state per release ID
    @State private var collectionStatusByReleaseId: [Int: CollectionStatus] = [:]
    @State private var loadingReleaseIDs = Set<Int>()
    @State private var statusLoadStartedAt: Date?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Offline indicator banner
                if !networkMonitor.isConnected {
                    offlineIndicatorBanner
                }
                
                // Match selection section
                matchSelectionSection
            }
            .padding(.vertical)
        }
        .navigationTitle("Select Match")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadInitialCollectionStatus()
        }
    }
    
    // MARK: - Collection Status Loading
    
    private var displayedMatches: [DiscogsMatch] {
        Array(discogsMatches.prefix(5))
    }

    @MainActor
    private func loadInitialCollectionStatus() async {
        guard !displayedMatches.isEmpty, networkMonitor.isConnected else { return }
        guard authService.isConnected else { return }

        statusLoadStartedAt = Date()

        if let first = displayedMatches.first {
            await loadStatus(for: first, forceRefresh: false)
        }

        if displayedMatches.count > 1 {
            await loadStatus(for: displayedMatches[1], forceRefresh: false)
        }
    }

    @MainActor
    private func loadStatus(for match: DiscogsMatch, forceRefresh: Bool) async {
        guard networkMonitor.isConnected else { return }
        guard authService.isConnected else { return }
        guard let username = authService.currentUsername, !username.isEmpty else { return }

        if !forceRefresh, let local = localLibraryStatus(for: match.releaseId) {
            collectionStatusByReleaseId[match.releaseId] = local.status
            await CollectionStatusStore.shared.updateCachedStatus(
                username: username,
                releaseId: match.releaseId,
                status: local.status
            )
            if local.isFresh {
                return
            }
        }

        if !forceRefresh, collectionStatusByReleaseId[match.releaseId] != nil {
            return
        }

        if loadingReleaseIDs.contains(match.releaseId) {
            return
        }

        loadingReleaseIDs.insert(match.releaseId)
        defer {
            loadingReleaseIDs.remove(match.releaseId)
        }

        do {
            let status = try await CollectionStatusStore.shared.status(
                username: username,
                releaseId: match.releaseId,
                forceRefresh: forceRefresh
            ) {
                try await DiscogsCollectionService.shared.checkCollectionStatus(
                    releaseId: match.releaseId,
                    username: username
                )
            }

            collectionStatusByReleaseId[match.releaseId] = status

            if collectionStatusByReleaseId.count == 1, let statusLoadStartedAt {
                let elapsed = Date().timeIntervalSince(statusLoadStartedAt)
                PerformanceMetrics.gauge("result_first_status_badge_seconds", value: elapsed)
            }
        } catch {
            // Silently fail for individual status checks - not critical
            print("Failed to check collection status for release \(match.releaseId): \(error)")
        }
    }

    @MainActor
    private func localLibraryStatus(for releaseId: Int) -> (status: CollectionStatus, isFresh: Bool)? {
        let inCollection = (try? libraryCache.containsLocalEntry(
            releaseId: releaseId,
            listType: .collection,
            in: modelContext
        )) ?? false
        let inWantlist = (try? libraryCache.containsLocalEntry(
            releaseId: releaseId,
            listType: .wantlist,
            in: modelContext
        )) ?? false

        let collectionRefresh: Date? = (try? libraryCache.lastRefreshDate(listType: .collection, in: modelContext)) ?? nil
        let wantlistRefresh: Date? = (try? libraryCache.lastRefreshDate(listType: .wantlist, in: modelContext)) ?? nil
        let latestRefresh = [collectionRefresh, wantlistRefresh].compactMap { $0 }.max()
        let isFresh = latestRefresh.map { Date().timeIntervalSince($0) <= libraryFreshInterval } ?? false

        guard inCollection || inWantlist || isFresh else {
            return nil
        }

        return (
            status: CollectionStatus(
                isInCollection: inCollection,
                isInWantlist: inWantlist
            ),
            isFresh: isFresh
        )
    }
    
    // MARK: - Offline Indicator
    
    private var offlineIndicatorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.subheadline)
            Text("Offline - Album artwork unavailable")
                .font(.subheadline)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange)
        .padding(.horizontal)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Match Selection Section
    
    private var matchSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text(matchHeaderText)
                    .font(.headline)
                Spacer()
                if !discogsMatches.isEmpty {
                    Text("\(displayedMatches.count) \(displayedMatches.count == 1 ? "match" : "matches")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            
            // Content: carousel, error, or empty state
            if !discogsMatches.isEmpty {
                // Show horizontal carousel of matches
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap a card to view full details")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    DiscogsMatchCarousel(
                        matches: displayedMatches,
                        collectionStatusByReleaseId: collectionStatusByReleaseId,
                        onMatchAppear: { match, _ in
                            Task {
                                await loadStatus(for: match, forceRefresh: false)
                            }
                        },
                        onMatchSelected: { match, index in
                            onMatchSelected(match, index)
                        }
                    )
                }
            } else if let error = discogsError {
                // Show error state when search failed
                errorStateView(error: error)
            } else {
                // Show empty state when search completed but found nothing
                emptyStateView
            }
        }
    }
    
    private var matchHeaderText: String {
        if !discogsMatches.isEmpty {
            return "Found Matches"
        } else if discogsError != nil {
            return "Search Error"
        } else {
            return "No Matches"
        }
    }
    
    private func errorStateView(error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Unable to search Discogs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("No matches found")
                    .font(.headline)
                
                Text("Discogs didn't find any matching releases for this record. Try scanning a clearer image or a different part of the record.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ResultView(
            image: UIImage(systemName: "photo")!,
            extractedData: ExtractedData(
                artist: "Miles Davis",
                album: "Kind of Blue",
                label: "Columbia",
                catalogNumber: "CL 1355",
                year: 1959,
                rawText: "Miles Davis - Kind of Blue, Columbia Records CL 1355, Released 1959",
                confidence: 0.92
            ),
            discogsMatches: [
                .sample(releaseId: 123456, title: "Kind of Blue", year: 1959, matchScore: 0.95),
                .sample(releaseId: 123457, title: "Kind of Blue (Reissue)", year: 1997, matchScore: 0.82),
                .sample(releaseId: 123458, title: "Kind of Blue (Limited Edition)", year: 2009, matchScore: 0.75)
            ],
            discogsError: nil,
            scanId: nil,
            onMatchSelected: { match, index in
                print("Preview: Selected \(match.title) at index \(index)")
            }
        )
    }
}
