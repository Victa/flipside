//
//  DetailView.swift
//  FlipSide
//
//  Displays detailed information about a selected Discogs release
//

import SwiftUI
import SwiftData

struct DetailView: View {
    let match: DiscogsMatch
    let scanId: UUID?
    let showDoneButton: Bool
    let onDone: () -> Void
    
    @StateObject private var viewModel = DetailViewModel()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var authService = DiscogsAuthService.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    private let libraryCache = SwiftDataLibraryCache.shared
    private let libraryFreshInterval: TimeInterval = 15 * 60
    
    // Collection status loading state
    @State private var isLoadingCollectionStatus = false
    @State private var isInCollection: Bool?
    @State private var isInWantlist: Bool?
    @State private var collectionError: String?
    
    // Collection action states
    @State private var isAddingToCollection = false
    @State private var isRemovingFromCollection = false
    @State private var isAddingToWantlist = false
    @State private var isRemovingFromWantlist = false
    
    // Use complete match if available, otherwise use basic match
    private var displayMatch: DiscogsMatch {
        viewModel.displayMatch ?? match
    }

    // Defensive dedupe for cached releases that may already include duplicate entries.
    private var displayVideos: [DiscogsMatch.Video] {
        viewModel.displayVideos(for: displayMatch)
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

    private func videoThumbnailURL(for uri: String) -> URL? {
        guard let youtubeID = youtubeVideoID(from: uri) else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(youtubeID)/hqdefault.jpg")
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Offline indicator banner
                if !networkMonitor.isConnected {
                    offlineIndicatorBanner
                }
                
                // Loading indicator
                if viewModel.isLoadingDetails {
                    loadingDetailsSection
                }
                
                // Album artwork
                albumArtworkSection
                
                // View on Discogs button
                viewOnDiscogsButton
                
                // Release information
                releaseInformationSection
                
                // Genres
                if !displayMatch.genres.isEmpty {
                    genresSection
                }
                
                // Styles (more specific than genres)
                if !displayMatch.styles.isEmpty {
                    stylesSection
                }
                
                // Formats (vinyl size, speed, etc.)
                if !displayMatch.formats.isEmpty {
                    formatsSection
                }
                
                // Tracklist
                if !displayMatch.tracklist.isEmpty {
                    tracklistSection
                }
                
                // Community stats
                if displayMatch.inCollection != nil || displayMatch.inWantlist != nil || displayMatch.numForSale != nil {
                    communityStatsSection
                }
                
                // Your Collection Section
                yourCollectionSection
                
                // Pricing information
                if let conditionPrices = displayMatch.conditionPrices, !conditionPrices.isEmpty {
                    pricingSection
                }
                
                // Identifiers (barcodes, matrix numbers)
                if !displayMatch.identifiers.isEmpty {
                    identifiersSection
                }
                
                // Videos
                if !displayVideos.isEmpty {
                    videosSection
                }
                
                // Notes
                if let notes = displayMatch.notes, !notes.isEmpty {
                    notesSection
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Release Details")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: displayMatch.releaseId) {
            await viewModel.loadCompleteDetailsIfNeeded(
                from: match,
                scanId: scanId,
                networkConnected: networkMonitor.isConnected,
                modelContext: modelContext
            )
            await loadCollectionStatus(forceRefresh: false)
        }
        .toolbar {
            if showDoneButton {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDone()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Offline Indicator
    
    private var offlineIndicatorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.subheadline)
            Text("Offline - Some content may be unavailable")
                .font(.subheadline)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange)
        .padding(.horizontal)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Loading Details Section
    
    private var loadingDetailsSection: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading complete details...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    
    // MARK: - Album Artwork Section
    
    private var albumArtworkSection: some View {
        VStack {
            if let imageUrl = displayMatch.imageUrl {
                CachedAsyncImage(url: imageUrl) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 8)
                } placeholder: {
                    ZStack {
                        Color(.secondarySystemGroupedBackground)
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                            Text("Artwork unavailable")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 350)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("No artwork available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 350)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Release Information Section
    
    private var releaseInformationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title and Artist
            VStack(alignment: .leading, spacing: 4) {
                Text(displayMatch.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(3)
                
                Text(displayMatch.artist)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            // Metadata (Year, Label, Catalog Number, Country, etc.)
            VStack(alignment: .leading, spacing: 8) {
                if let year = displayMatch.year {
                    metadataRow(
                        icon: "calendar",
                        label: "Year",
                        value: "\(year)"
                    )
                }
                
                if let released = displayMatch.released {
                    metadataRow(
                        icon: "calendar.badge.clock",
                        label: "Released",
                        value: released
                    )
                }
                
                if let country = displayMatch.country {
                    metadataRow(
                        icon: "globe",
                        label: "Country",
                        value: country
                    )
                }
                
                if let label = displayMatch.label {
                    metadataRow(
                        icon: "building.2",
                        label: "Label",
                        value: label
                    )
                }
                
                if let catalogNumber = displayMatch.catalogNumber {
                    metadataRow(
                        icon: "number",
                        label: "Catalog #",
                        value: catalogNumber
                    )
                }
                
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }
    
    // MARK: - Genres Section
    
    private var genresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Genres")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(displayMatch.genres, id: \.self) { genre in
                        Text(genre)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Styles Section
    
    private var stylesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Styles")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(displayMatch.styles, id: \.self) { style in
                        Text(style)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Formats Section
    
    private var formatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Format")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(displayMatch.formats.enumerated()), id: \.offset) { _, format in
                    HStack {
                        Image(systemName: "opticaldisc")
                            .font(.subheadline)
                            .foregroundStyle(.purple)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(format.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            if let descriptions = format.descriptions, !descriptions.isEmpty {
                                Text(descriptions.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let text = format.text, !text.isEmpty {
                                Text(text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if let qty = format.qty {
                            Text("×\(qty)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }
    
    // MARK: - Tracklist Section
    
    private var tracklistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracklist")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(displayMatch.tracklist.enumerated()), id: \.offset) { _, track in
                    HStack(alignment: .top) {
                        // Position
                        Text(track.position)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .leading)
                        
                        // Title and artists
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.subheadline)
                            
                            if let artists = track.artists, !artists.isEmpty {
                                Text(artists.map { $0.name }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Duration
                        if let duration = track.duration, !duration.isEmpty {
                            Text(duration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if track != displayMatch.tracklist.last {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }
    
    // MARK: - Community Stats Section
    
    private var communityStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Community")
                .font(.headline)
            
            VStack(spacing: 8) {
                if let have = displayMatch.inCollection {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                        
                        Text("Have")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("\(have)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                
                if let want = displayMatch.inWantlist {
                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.subheadline)
                            .foregroundStyle(.pink)
                        
                        Text("Want")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("\(want)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                
                if let forSale = displayMatch.numForSale {
                    HStack {
                        Image(systemName: "cart.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        
                        Text("For Sale")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("\(forSale)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }
    
    // MARK: - Pricing Section
    
    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested Pricing")
                .font(.headline)
            
            VStack(spacing: 8) {
                if let conditionPrices = displayMatch.conditionPrices, !conditionPrices.isEmpty {
                    // Define the desired display order (highest to lowest condition)
                    let conditionOrder = [
                        "Mint (M)",
                        "Near Mint (NM or M-)",
                        "Very Good Plus (VG+)",
                        "Very Good (VG)",
                        "Good Plus (G+)",
                        "Good (G)",
                        "Fair (F)",
                        "Poor (P)"
                    ]
                    
                    // Display conditions in the specified order (only those available)
                    ForEach(conditionOrder, id: \.self) { conditionName in
                        if let priceData = conditionPrices[conditionName] {
                            pricingRow(
                                icon: iconForCondition(conditionName),
                                iconColor: colorForCondition(conditionName),
                                label: conditionName,
                                price: priceData.value,
                                priceColor: colorForCondition(conditionName)
                            )
                        }
                    }
                    
                    Text("Based on Discogs marketplace sales data")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }
    
    private func pricingRow(icon: String, iconColor: Color, label: String, price: Decimal, priceColor: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(iconColor)
            
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(formatPrice(price))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(priceColor)
        }
    }
    
    private func formatPrice(_ price: Decimal) -> String {
        viewModel.formatPrice(price)
    }
    
    /// Return appropriate icon for condition grade
    private func iconForCondition(_ condition: String) -> String {
        switch condition {
        case "Mint (M)":
            return "star.fill"
        case "Near Mint (NM or M-)":
            return "arrow.up.circle.fill"
        case "Very Good Plus (VG+)":
            return "chart.bar.fill"
        case "Very Good (VG)":
            return "tag.fill"
        case "Good Plus (G+)":
            return "tag"
        case "Good (G)":
            return "circle"
        case "Fair (F)":
            return "circle.dotted"
        case "Poor (P)":
            return "exclamationmark.circle"
        default:
            return "tag.fill"
        }
    }
    
    /// Return appropriate color for condition grade
    private func colorForCondition(_ condition: String) -> Color {
        switch condition {
        case "Mint (M)":
            return .purple
        case "Near Mint (NM or M-)":
            return .orange
        case "Very Good Plus (VG+)":
            return .blue
        case "Very Good (VG)":
            return .green
        case "Good Plus (G+)":
            return .teal
        case "Good (G)":
            return .yellow
        case "Fair (F)":
            return .gray
        case "Poor (P)":
            return .red
        default:
            return .primary
        }
    }
    
    // MARK: - Identifiers Section
    
    private var identifiersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Identifiers")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(displayMatch.identifiers.enumerated()), id: \.offset) { _, identifier in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(identifier.type)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        Text(identifier.value)
                            .font(.subheadline)
                            .textSelection(.enabled)
                        
                        if let description = identifier.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if identifier != displayMatch.identifiers.last {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }
    
    // MARK: - Videos Section
    
    private var videosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Videos (\(displayVideos.count))")
                .font(.headline)
            
            VStack(spacing: 12) {
                ForEach(Array(displayVideos.enumerated()), id: \.offset) { _, video in
                    Button {
                        if let url = URL(string: video.uri) {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Group {
                                if let thumbnailURL = videoThumbnailURL(for: video.uri) {
                                    CachedAsyncImage(url: thumbnailURL) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        ZStack {
                                            Color(.tertiarySystemFill)
                                            Image(systemName: "play.rectangle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                } else {
                                    ZStack {
                                        Color(.tertiarySystemFill)
                                        Image(systemName: "play.rectangle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(width: 84, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(video.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                
                                if let description = video.description, !description.isEmpty {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                
                                if let duration = video.duration {
                                    Text(formatDuration(duration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.headline)
            
            Text(displayMatch.notes ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }
    
    // MARK: - View on Discogs Button
    
    private var viewOnDiscogsButton: some View {
        Button {
            if let url = DiscogsService.shared.generateReleaseURL(releaseId: displayMatch.releaseId) {
                openURL(url)
            }
        } label: {
            HStack {
                Image(systemName: "safari")
                    .font(.headline)
                Text("View on Discogs")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - Helper Views
    
    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.blue)
                .frame(width: 20)
            
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
        }
    }
    
    // MARK: - Your Collection Section
    
    private var yourCollectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Collection")
                .font(.headline)
            
            if let error = collectionError {
                // Error state
                VStack(spacing: 12) {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    
                    if error.contains("username") || error.contains("connect") || error.contains("OAuth") {
                        Button("Go to Settings") {
                            // Open settings (would need to pass a binding or closure)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Retry") {
                            Task {
                                await loadCollectionStatus(forceRefresh: true)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if isLoadingCollectionStatus {
                // Loading state
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Checking collection status...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Status and action buttons
                VStack(spacing: 12) {
                    // Collection status
                    HStack {
                        Image(systemName: isInCollection == true ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isInCollection == true ? .green : .secondary)
                        
                        Text(isInCollection == true ? "In Your Collection" : "Not in Collection")
                            .font(.subheadline)
                            .foregroundStyle(isInCollection == true ? .primary : .secondary)
                        
                        Spacer()
                        
                        if isAddingToCollection || isRemovingFromCollection {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Button {
                                Task {
                                    if isInCollection == true {
                                        await removeFromCollection()
                                    } else {
                                        await addToCollection()
                                    }
                                }
                            } label: {
                                Text(isInCollection == true ? "Remove" : "Add")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isAddingToCollection || isRemovingFromCollection)
                        }
                    }
                    
                    Divider()
                    
                    // Wantlist status
                    HStack {
                        Image(systemName: isInWantlist == true ? "heart.fill" : "heart")
                            .font(.title3)
                            .foregroundStyle(isInWantlist == true ? .pink : .secondary)
                        
                        Text(isInWantlist == true ? "In Your Wantlist" : "Not in Wantlist")
                            .font(.subheadline)
                            .foregroundStyle(isInWantlist == true ? .primary : .secondary)
                        
                        Spacer()
                        
                        if isAddingToWantlist || isRemovingFromWantlist {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Button {
                                Task {
                                    if isInWantlist == true {
                                        await removeFromWantlist()
                                    } else {
                                        await addToWantlist()
                                    }
                                }
                            } label: {
                                Text(isInWantlist == true ? "Remove" : "Add")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isAddingToWantlist || isRemovingFromWantlist)
                        }
                    }
                    
                    // Refresh button
                    Button {
                        Task {
                            await loadCollectionStatus(forceRefresh: true)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh Status")
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(isLoadingCollectionStatus)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Collection Action Methods
    
    private func loadCollectionStatus(forceRefresh: Bool) async {
        // Load cached scan data to show immediately (but always refresh from API when online)
        if let scanId = scanId {
            let fetchDescriptor = FetchDescriptor<Scan>(
                predicate: #Predicate { $0.id == scanId }
            )
            
            if let scan = try? modelContext.fetch(fetchDescriptor).first {
                // Show cached values immediately while we refresh in the background
                if scan.isInCollection != nil || scan.isInWantlist != nil {
                    await MainActor.run {
                        isInCollection = scan.isInCollection
                        isInWantlist = scan.isInWantlist
                    }
                    
                    // If offline, use cached data only
                    if !networkMonitor.isConnected {
                        return
                    }
                    // Otherwise, continue to refresh from API below
                }
            }
        }

        if !forceRefresh, let local = localLibraryStatus(releaseId: displayMatch.releaseId) {
            await MainActor.run {
                isInCollection = local.status.isInCollection
                isInWantlist = local.status.isInWantlist
                updateScanCollectionStatus(
                    isInCollection: local.status.isInCollection,
                    isInWantlist: local.status.isInWantlist
                )
            }

            if let username = authService.currentUsername, !username.isEmpty {
                await CollectionStatusStore.shared.updateCachedStatus(
                    username: username,
                    releaseId: displayMatch.releaseId,
                    status: local.status
                )
            }

            if local.isFresh {
                return
            }
        }
        
        guard authService.isConnected else {
            await MainActor.run {
                collectionError = "Discogs account not connected. Please connect in Settings."
            }
            return
        }
        
        guard let username = authService.currentUsername, !username.isEmpty else {
            await MainActor.run {
                collectionError = "Discogs username unavailable. Please reconnect in Settings."
            }
            return
        }
        
        await MainActor.run {
            isLoadingCollectionStatus = true
            collectionError = nil
        }
        
        do {
            let status = try await CollectionStatusStore.shared.status(
                username: username,
                releaseId: displayMatch.releaseId,
                forceRefresh: forceRefresh
            ) {
                try await DiscogsCollectionService.shared.checkCollectionStatus(
                    releaseId: displayMatch.releaseId,
                    username: username
                )
            }

            await MainActor.run {
                isInCollection = status.isInCollection
                isInWantlist = status.isInWantlist
                isLoadingCollectionStatus = false
                updateScanCollectionStatus(isInCollection: status.isInCollection, isInWantlist: status.isInWantlist)
            }
        } catch {
            await MainActor.run {
                collectionError = error.localizedDescription
                isLoadingCollectionStatus = false
            }
        }
    }
    
    private func addToCollection() async {
        guard let username = authService.currentUsername else { return }
        let action = "add_collection"
        let mutationStartedAt = Date()
        
        await MainActor.run {
            isAddingToCollection = true
            collectionError = nil
        }
        await CollectionStatusStore.shared.invalidate(username: username, releaseId: displayMatch.releaseId)
        
        do {
            try await DiscogsCollectionService.shared.addToCollection(
                releaseId: displayMatch.releaseId,
                username: username
            )
            logDurationMetric(
                "library_mutation_request_duration_seconds",
                action: action,
                startedAt: mutationStartedAt
            )

            let optimisticStartedAt = Date()
            let optimisticWantlist = isInWantlist
            await MainActor.run {
                do {
                    try libraryCache.upsertLocalEntry(from: displayMatch, listType: .collection, in: modelContext)
                } catch {
                    print("Optimistic cache update failed for action=\(action): \(error.localizedDescription)")
                }
                isInCollection = true
                isAddingToCollection = false
                updateScanCollectionStatus(isInCollection: true, isInWantlist: optimisticWantlist)
            }
            logDurationMetric(
                "library_optimistic_completion_duration_seconds",
                action: action,
                startedAt: optimisticStartedAt
            )
            await CollectionStatusStore.shared.updateCachedStatus(
                username: username,
                releaseId: displayMatch.releaseId,
                status: CollectionStatus(
                    isInCollection: true,
                    isInWantlist: optimisticWantlist ?? false,
                    collectionInstanceId: nil
                )
            )
        } catch {
            await MainActor.run {
                isAddingToCollection = false
                collectionError = "Failed to add to collection: \(error.localizedDescription)"
            }
        }
    }
    
    private func removeFromCollection() async {
        guard let username = authService.currentUsername else { return }
        let action = "remove_collection"
        let mutationStartedAt = Date()
        
        await MainActor.run {
            isRemovingFromCollection = true
            collectionError = nil
        }
        await CollectionStatusStore.shared.invalidate(username: username, releaseId: displayMatch.releaseId)
        
        do {
            try await DiscogsCollectionService.shared.removeFromCollection(
                releaseId: displayMatch.releaseId,
                username: username
            )
            logDurationMetric(
                "library_mutation_request_duration_seconds",
                action: action,
                startedAt: mutationStartedAt
            )

            let optimisticStartedAt = Date()
            let optimisticWantlist = isInWantlist
            await MainActor.run {
                do {
                    try libraryCache.removeOneLocalEntry(
                        releaseId: displayMatch.releaseId,
                        listType: .collection,
                        in: modelContext
                    )
                } catch {
                    print("Optimistic cache update failed for action=\(action): \(error.localizedDescription)")
                }
                isInCollection = false
                isRemovingFromCollection = false
                updateScanCollectionStatus(isInCollection: false, isInWantlist: optimisticWantlist)
            }
            logDurationMetric(
                "library_optimistic_completion_duration_seconds",
                action: action,
                startedAt: optimisticStartedAt
            )
            await CollectionStatusStore.shared.updateCachedStatus(
                username: username,
                releaseId: displayMatch.releaseId,
                status: CollectionStatus(
                    isInCollection: false,
                    isInWantlist: optimisticWantlist ?? false,
                    collectionInstanceId: nil
                )
            )
        } catch {
            await MainActor.run {
                isRemovingFromCollection = false
                collectionError = "Failed to remove from collection: \(error.localizedDescription)"
            }
        }
    }
    
    private func addToWantlist() async {
        guard let username = authService.currentUsername else { return }
        let action = "add_wantlist"
        let mutationStartedAt = Date()
        
        await MainActor.run {
            isAddingToWantlist = true
            collectionError = nil
        }
        await CollectionStatusStore.shared.invalidate(username: username, releaseId: displayMatch.releaseId)
        
        do {
            try await DiscogsCollectionService.shared.addToWantlist(
                releaseId: displayMatch.releaseId,
                username: username
            )
            logDurationMetric(
                "library_mutation_request_duration_seconds",
                action: action,
                startedAt: mutationStartedAt
            )

            let optimisticStartedAt = Date()
            let optimisticCollection = isInCollection
            await MainActor.run {
                do {
                    try libraryCache.upsertLocalEntry(from: displayMatch, listType: .wantlist, in: modelContext)
                } catch {
                    print("Optimistic cache update failed for action=\(action): \(error.localizedDescription)")
                }
                isInWantlist = true
                isAddingToWantlist = false
                updateScanCollectionStatus(isInCollection: optimisticCollection, isInWantlist: true)
            }
            logDurationMetric(
                "library_optimistic_completion_duration_seconds",
                action: action,
                startedAt: optimisticStartedAt
            )
            await CollectionStatusStore.shared.updateCachedStatus(
                username: username,
                releaseId: displayMatch.releaseId,
                status: CollectionStatus(
                    isInCollection: optimisticCollection ?? false,
                    isInWantlist: true,
                    collectionInstanceId: nil
                )
            )
        } catch {
            await MainActor.run {
                isAddingToWantlist = false
                collectionError = "Failed to add to wantlist: \(error.localizedDescription)"
            }
        }
    }
    
    private func removeFromWantlist() async {
        guard let username = authService.currentUsername else { return }
        let action = "remove_wantlist"
        let mutationStartedAt = Date()
        
        await MainActor.run {
            isRemovingFromWantlist = true
            collectionError = nil
        }
        await CollectionStatusStore.shared.invalidate(username: username, releaseId: displayMatch.releaseId)
        
        do {
            try await DiscogsCollectionService.shared.removeFromWantlist(
                releaseId: displayMatch.releaseId,
                username: username
            )
            logDurationMetric(
                "library_mutation_request_duration_seconds",
                action: action,
                startedAt: mutationStartedAt
            )

            let optimisticStartedAt = Date()
            let optimisticCollection = isInCollection
            await MainActor.run {
                do {
                    try libraryCache.removeAllLocalEntries(
                        releaseId: displayMatch.releaseId,
                        listType: .wantlist,
                        in: modelContext
                    )
                } catch {
                    print("Optimistic cache update failed for action=\(action): \(error.localizedDescription)")
                }
                isInWantlist = false
                isRemovingFromWantlist = false
                updateScanCollectionStatus(isInCollection: optimisticCollection, isInWantlist: false)
            }
            logDurationMetric(
                "library_optimistic_completion_duration_seconds",
                action: action,
                startedAt: optimisticStartedAt
            )
            await CollectionStatusStore.shared.updateCachedStatus(
                username: username,
                releaseId: displayMatch.releaseId,
                status: CollectionStatus(
                    isInCollection: optimisticCollection ?? false,
                    isInWantlist: false,
                    collectionInstanceId: nil
                )
            )
        } catch {
            await MainActor.run {
                isRemovingFromWantlist = false
                collectionError = "Failed to remove from wantlist: \(error.localizedDescription)"
            }
        }
    }
    
    private func updateScanCollectionStatus(isInCollection: Bool?, isInWantlist: Bool?) {
        guard let scanId = scanId else { return }
        
        let fetchDescriptor = FetchDescriptor<Scan>(
            predicate: #Predicate { $0.id == scanId }
        )
        
        if let scan = try? modelContext.fetch(fetchDescriptor).first {
            scan.isInCollection = isInCollection
            scan.isInWantlist = isInWantlist
            try? modelContext.save()
        }
    }

    private func localLibraryStatus(releaseId: Int) -> (status: CollectionStatus, isFresh: Bool)? {
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

    private func logDurationMetric(_ metricName: String, action: String, startedAt: Date) {
        let duration = Date().timeIntervalSince(startedAt)
        print("metric \(metricName)=\(String(format: "%.2f", duration))s action=\(action)")
    }
    
    // MARK: - Helper Methods
    
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DetailView(
            match: DiscogsMatch(
                releaseId: 123456,
                title: "Kind of Blue",
                artist: "Miles Davis",
                year: 1959,
                released: "1959-08-17",
                country: "US",
                label: "Columbia",
                catalogNumber: "CL 1355",
                matchScore: 0.95,
                imageUrl: URL(string: "https://example.com/image.jpg"),
                thumbnailUrl: nil,
                genres: ["Jazz", "Cool Jazz", "Modal"],
                styles: ["Bebop", "Hard Bop"],
                formats: [
                    DiscogsMatch.Format(name: "Vinyl", qty: "1", descriptions: ["LP", "Album", "Mono"], text: nil)
                ],
                tracklist: [
                    DiscogsMatch.TracklistItem(position: "A1", title: "So What", duration: "9:22", artists: nil, extraartists: nil),
                    DiscogsMatch.TracklistItem(position: "A2", title: "Freddie Freeloader", duration: "9:33", artists: nil, extraartists: nil)
                ],
                identifiers: [
                    DiscogsMatch.Identifier(type: "Matrix / Runout", value: "XLP 47935-1A", description: "Side A")
                ],
                conditionPrices: [
                    "Mint (M)": DiscogsMatch.ConditionPrice(currency: "USD", value: 85.00),
                    "Near Mint (NM or M-)": DiscogsMatch.ConditionPrice(currency: "USD", value: 75.00),
                    "Very Good Plus (VG+)": DiscogsMatch.ConditionPrice(currency: "USD", value: 35.00),
                    "Very Good (VG)": DiscogsMatch.ConditionPrice(currency: "USD", value: 24.99),
                    "Good Plus (G+)": DiscogsMatch.ConditionPrice(currency: "USD", value: 18.00),
                    "Good (G)": DiscogsMatch.ConditionPrice(currency: "USD", value: 12.00)
                ],
                numForSale: 42,
                inWantlist: 1523,
                inCollection: 3891,
                notes: "Classic jazz album recorded in 1959.",
                dataQuality: "Correct",
                masterId: 12345,
                uri: "/release/123456",
                resourceUrl: "https://api.discogs.com/releases/123456",
                videos: [
                    DiscogsMatch.Video(uri: "https://www.youtube.com/watch?v=example", title: "So What - Music Video", description: "Official", duration: 562)
                ]
            ),
            scanId: nil,
            showDoneButton: true,
            onDone: {
                print("Done tapped")
            }
        )
    }
}
