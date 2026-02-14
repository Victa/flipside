//
//  ResultView.swift
//  FlipSide
//
//  Displays extracted vinyl record information
//

import SwiftUI

struct ResultView: View {
    let image: UIImage
    let extractedData: ExtractedData
    let discogsMatches: [DiscogsMatch]
    let discogsError: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Captured image
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
                    .padding(.horizontal)
                
                // Discogs matches section (always shown with status)
                discogsMatchesSection
                
                // Confidence indicator
                confidenceSection
                
                // Extracted fields
                extractedFieldsSection
                
                // Raw text section
                rawTextSection
            }
            .padding(.vertical)
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Discogs Matches Section
    
    private var discogsMatchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discogs Matches")
                .font(.headline)
                .padding(.horizontal)
            
            if !discogsMatches.isEmpty {
                // Show match cards when matches are found
                VStack(spacing: 12) {
                    ForEach(Array(discogsMatches.prefix(5).enumerated()), id: \.element.releaseId) { index, match in
                        DiscogsMatchCard(match: match, rank: index + 1)
                    }
                }
                .padding(.horizontal)
            } else if let error = discogsError {
                // Show error message when search failed
                VStack(spacing: 12) {
                    HStack {
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
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            } else {
                // Show "no results" message when search completed but found nothing
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No matches found")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Text("Discogs didn't find any matching releases for this record.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Confidence Section
    
    private var confidenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Confidence")
                    .font(.headline)
                Spacer()
                Text(confidenceText)
                    .font(.subheadline)
                    .foregroundStyle(confidenceColor)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(confidenceColor)
                        .frame(
                            width: geometry.size.width * extractedData.confidence,
                            height: 8
                        )
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal)
    }
    
    private var confidenceText: String {
        let percentage = Int(extractedData.confidence * 100)
        return "\(percentage)%"
    }
    
    private var confidenceColor: Color {
        switch extractedData.confidence {
        case 0.8...1.0:
            return .green
        case 0.6..<0.8:
            return .orange
        default:
            return .red
        }
    }
    
    // MARK: - Extracted Fields Section
    
    private var extractedFieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Extracted Information")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 0) {
                if let artist = extractedData.artist {
                    ExtractedFieldRow(label: "Artist", value: artist)
                    Divider()
                }
                
                if let album = extractedData.album {
                    ExtractedFieldRow(label: "Album", value: album)
                    Divider()
                }
                
                if let label = extractedData.label {
                    ExtractedFieldRow(label: "Label", value: label)
                    Divider()
                }
                
                if let catalogNumber = extractedData.catalogNumber {
                    ExtractedFieldRow(label: "Catalog #", value: catalogNumber)
                    Divider()
                }
                
                if let year = extractedData.year {
                    ExtractedFieldRow(label: "Year", value: String(year))
                    if extractedData.tracks != nil {
                        Divider()
                    }
                }
                
                // Tracks section (important for singles and EPs)
                if let tracks = extractedData.tracks, !tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tracks")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                            HStack(alignment: .top, spacing: 8) {
                                Text(track.position)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, alignment: .leading)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.body)
                                    
                                    if let trackArtist = track.artist {
                                        Text(trackArtist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 8)
                    }
                }
                
                // Show message if no fields were extracted
                if extractedData.artist == nil &&
                   extractedData.album == nil &&
                   extractedData.label == nil &&
                   extractedData.catalogNumber == nil &&
                   extractedData.year == nil &&
                   extractedData.tracks == nil {
                    Text("No structured information extracted")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }
    
    // MARK: - Raw Text Section
    
    private var rawTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw Text")
                .font(.headline)
                .padding(.horizontal)
            
            Text(extractedData.rawText)
                .font(.body)
                .foregroundStyle(.primary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
        }
    }
}

// MARK: - Supporting Views

struct DiscogsMatchCard: View {
    let match: DiscogsMatch
    let rank: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with rank and confidence score
            HStack {
                // Rank badge
                Text("#\(rank)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(rankColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                
                Spacer()
                
                // Confidence score
                HStack(spacing: 4) {
                    Image(systemName: confidenceIcon)
                        .font(.caption)
                    Text(confidenceText)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(confidenceColor)
            }
            
            // Album cover image
            if let imageUrl = match.imageUrl {
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            
            // Release details
            VStack(alignment: .leading, spacing: 4) {
                Text(match.title)
                    .font(.headline)
                    .lineLimit(2)
                
                Text(match.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack {
                    if let year = match.year {
                        Text("\(year)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let label = match.label {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    if let catalogNumber = match.catalogNumber {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(catalogNumber)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Genres
                if !match.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(match.genres.prefix(3), id: \.self) { genre in
                                Text(genre)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                
                // Pricing info (if available)
                if let lowestPrice = match.lowestPrice {
                    HStack {
                        Image(systemName: "tag.fill")
                            .font(.caption)
                        Text("From $\(lowestPrice as NSDecimalNumber)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Computed Properties
    
    private var rankColor: Color {
        switch rank {
        case 1: return .blue
        case 2: return .purple
        case 3: return .orange
        default: return .gray
        }
    }
    
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
}

struct ExtractedFieldRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding()
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
                DiscogsMatch(
                    releaseId: 123456,
                    title: "Kind of Blue",
                    artist: "Miles Davis",
                    year: 1959,
                    label: "Columbia",
                    catalogNumber: "CL 1355",
                    matchScore: 0.95,
                    imageUrl: URL(string: "https://i.discogs.com/example.jpg"),
                    genres: ["Jazz", "Cool Jazz", "Modal"],
                    lowestPrice: 29.99,
                    medianPrice: 45.00
                ),
                DiscogsMatch(
                    releaseId: 123457,
                    title: "Kind of Blue (Reissue)",
                    artist: "Miles Davis",
                    year: 1997,
                    label: "Columbia",
                    catalogNumber: "CK 64935",
                    matchScore: 0.82,
                    imageUrl: URL(string: "https://i.discogs.com/example2.jpg"),
                    genres: ["Jazz", "Cool Jazz"],
                    lowestPrice: 19.99,
                    medianPrice: 30.00
                ),
                DiscogsMatch(
                    releaseId: 123458,
                    title: "Kind of Blue (Limited Edition)",
                    artist: "Miles Davis",
                    year: 2009,
                    label: "Columbia/Legacy",
                    catalogNumber: "88697 49698 1",
                    matchScore: 0.75,
                    imageUrl: nil,
                    genres: ["Jazz"],
                    lowestPrice: nil,
                    medianPrice: nil
                )
            ],
            discogsError: nil
        )
    }
}
