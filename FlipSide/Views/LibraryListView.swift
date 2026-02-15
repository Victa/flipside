import SwiftUI
import SwiftData

struct LibraryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [LibraryEntry]
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var authService = DiscogsAuthService.shared

    @ObservedObject var viewModel: DiscogsLibraryViewModel
    let listType: LibraryListType
    let onSelect: (LibraryEntry) -> Void

    init(
        listType: LibraryListType,
        viewModel: DiscogsLibraryViewModel,
        onSelect: @escaping (LibraryEntry) -> Void
    ) {
        self.listType = listType
        self.viewModel = viewModel
        self.onSelect = onSelect

        let listTypeRaw = listType.rawValue
        _entries = Query(
            filter: #Predicate<LibraryEntry> { entry in
                entry.listTypeRaw == listTypeRaw
            },
            sort: [
                SortDescriptor(\LibraryEntry.dateAdded, order: .reverse),
                SortDescriptor(\LibraryEntry.title, order: .forward)
            ]
        )
    }

    private var state: DiscogsLibraryViewModel.ListState {
        viewModel.state(for: listType)
    }

    private var accountConnected: Bool {
        authService.isConnected && (authService.currentUsername?.isEmpty == false)
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                if state.isRefreshing {
                    VStack(spacing: 8) {
                        ProgressView("Loading \(listType.title)...")
                        Text(backgroundSyncBannerText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyStateView
                }
            } else {
                List(entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        rowView(for: entry)
                    }
                    .buttonStyle(.plain)
                }
                .overlay(alignment: .top) {
                    if !networkMonitor.isConnected {
                        Text("Offline - showing cached \(listType.title.lowercased())")
                            .font(.caption)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                            .padding(.top, 8)
                    } else if state.isBackgroundRefreshing {
                        Text(backgroundSyncBannerText)
                            .font(.caption)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                            .padding(.top, 8)
                    } else if let errorMessage = state.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                }
            }
        }
        .task {
            viewModel.prepareState(listType: listType, modelContext: modelContext)
            await viewModel.refreshIfStale(listType: listType, modelContext: modelContext)
        }
        .refreshable {
            _ = await viewModel.refresh(listType: listType, modelContext: modelContext)
        }
    }

    private var backgroundSyncBannerText: String {
        let pageText: String
        if state.totalPages > 0 {
            pageText = "Syncing page \(max(state.pagesLoaded, 1))/\(state.totalPages)"
        } else {
            pageText = "Syncing pages"
        }
        return "\(pageText)... (\(state.itemsLoadedCount) items loaded)"
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: listType == .collection ? "square.stack.3d.up" : "heart")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            Text(emptyTitle)
                .font(.headline)

            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let lastRefresh = state.lastRefreshDate {
                Text("Last refreshed: \(lastRefresh.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if !accountConnected {
            return "Connect your Discogs account"
        }

        switch listType {
        case .collection:
            return "No collection items cached"
        case .wantlist:
            return "No wantlist items cached"
        }
    }

    private var emptyMessage: String {
        if !accountConnected {
            return "Open Settings and connect Discogs, then run Refresh Collection/Wantlist."
        }

        if !networkMonitor.isConnected {
            return "You're offline. Cached library items will appear here when available."
        }

        if state.errorMessage != nil {
            return "Unable to refresh right now. Cached results will appear here when available."
        }

        return "Pull to refresh or run Refresh Collection/Wantlist from Settings."
    }

    private func rowView(for entry: LibraryEntry) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: entry.imageURLString.flatMap(URL.init(string:))) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ZStack {
                    Color.gray.opacity(0.2)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(entry.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                let yearCountry = [
                    entry.year.map(String.init),
                    entry.country
                ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " - ")

                if !yearCountry.isEmpty {
                    Text(yearCountry)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let formatSummary = entry.formatSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !formatSummary.isEmpty {
                    Text(formatSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                let labelCatalog = [
                    entry.label,
                    entry.catalogNumber
                ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " - ")

                if !labelCatalog.isEmpty {
                    Text(labelCatalog)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
