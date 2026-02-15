//
//  DetailView.swift
//  FlipSide
//
//  Displays detailed information about a selected Discogs release
//

import SwiftUI

struct DetailView: View {
    let match: DiscogsMatch
    let onDone: () -> Void
    
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Offline indicator banner
                if !networkMonitor.isConnected {
                    offlineIndicatorBanner
                }
                
                // Album artwork
                albumArtworkSection
                
                // Release information
                releaseInformationSection
                
                // Genres
                if !match.genres.isEmpty {
                    genresSection
                }
                
                // Styles (more specific than genres)
                if !match.styles.isEmpty {
                    stylesSection
                }
                
                // Formats (vinyl size, speed, etc.)
                if !match.formats.isEmpty {
                    formatsSection
                }
                
                // Tracklist
                if !match.tracklist.isEmpty {
                    tracklistSection
                }
                
                // Community stats
                if match.inCollection != nil || match.inWantlist != nil || match.numForSale != nil {
                    communityStatsSection
                }
                
                // Pricing information
                if match.lowestPrice != nil || match.medianPrice != nil {
                    pricingSection
                }
                
                // Identifiers (barcodes, matrix numbers)
                if !match.identifiers.isEmpty {
                    identifiersSection
                }
                
                // Videos
                if !match.videos.isEmpty {
                    videosSection
                }
                
                // Notes
                if let notes = match.notes, !notes.isEmpty {
                    notesSection
                }
                
                // View on Discogs button
                viewOnDiscogsButton
            }
            .padding(.vertical)
        }
        .navigationTitle("Release Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    onDone()
                }
                .fontWeight(.semibold)
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
    
    // MARK: - Album Artwork Section
    
    private var albumArtworkSection: some View {
        VStack {
            if let imageUrl = match.imageUrl {
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color(.secondarySystemGroupedBackground)
                            ProgressView()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 350)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 8)
                        
                    case .failure:
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                            Text("Artwork unavailable")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 350)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                    @unknown default:
                        EmptyView()
                    }
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
                Text(match.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(3)
                
                Text(match.artist)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            // Metadata (Year, Label, Catalog Number, Country, etc.)
            VStack(alignment: .leading, spacing: 8) {
                if let year = match.year {
                    metadataRow(
                        icon: "calendar",
                        label: "Year",
                        value: "\(year)"
                    )
                }
                
                if let released = match.released {
                    metadataRow(
                        icon: "calendar.badge.clock",
                        label: "Released",
                        value: released
                    )
                }
                
                if let country = match.country {
                    metadataRow(
                        icon: "globe",
                        label: "Country",
                        value: country
                    )
                }
                
                if let label = match.label {
                    metadataRow(
                        icon: "building.2",
                        label: "Label",
                        value: label
                    )
                }
                
                if let catalogNumber = match.catalogNumber {
                    metadataRow(
                        icon: "number",
                        label: "Catalog #",
                        value: catalogNumber
                    )
                }
                
                // Match confidence score
                HStack(spacing: 8) {
                    Image(systemName: confidenceIcon)
                        .font(.subheadline)
                        .foregroundStyle(confidenceColor)
                    
                    Text("Match Confidence")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)
                    
                    Text(confidenceText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(confidenceColor)
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
                    ForEach(match.genres, id: \.self) { genre in
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
                    ForEach(match.styles, id: \.self) { style in
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
                ForEach(Array(match.formats.enumerated()), id: \.offset) { _, format in
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
                ForEach(Array(match.tracklist.enumerated()), id: \.offset) { _, track in
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
                    
                    if track != match.tracklist.last {
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
                if let have = match.inCollection {
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
                
                if let want = match.inWantlist {
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
                
                if let forSale = match.numForSale {
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
            Text("Marketplace Pricing")
                .font(.headline)
            
            VStack(spacing: 8) {
                if let lowestPrice = match.lowestPrice {
                    HStack {
                        Image(systemName: "tag.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        
                        Text("Lowest Price")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("$\(lowestPrice as NSDecimalNumber)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                }
                
                if let medianPrice = match.medianPrice {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                        
                        Text("Median Price")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("$\(medianPrice as NSDecimalNumber)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }
    
    // MARK: - Identifiers Section
    
    private var identifiersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Identifiers")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(match.identifiers.enumerated()), id: \.offset) { _, identifier in
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
                    
                    if identifier != match.identifiers.last {
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
            Text("Videos")
                .font(.headline)
            
            VStack(spacing: 12) {
                ForEach(Array(match.videos.enumerated()), id: \.offset) { _, video in
                    Button {
                        if let url = URL(string: video.uri) {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                            
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
            
            Text(match.notes ?? "")
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
            if let url = DiscogsService.shared.generateReleaseURL(releaseId: match.releaseId) {
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
    
    // MARK: - Computed Properties
    
    private var confidenceText: String {
        String(format: "%.0f%% match", match.matchScore * 100)
    }
    
    private var confidenceColor: Color {
        switch match.matchScore {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .orange
        default: return .red
        }
    }
    
    private var confidenceIcon: String {
        switch match.matchScore {
        case 0.8...1.0: return "checkmark.circle.fill"
        case 0.6..<0.8: return "exclamationmark.circle.fill"
        default: return "questionmark.circle.fill"
        }
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
                lowestPrice: 24.99,
                medianPrice: 35.00,
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
            onDone: {
                print("Done tapped")
            }
        )
    }
}
