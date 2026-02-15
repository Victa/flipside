//
//  DetailView.swift
//  FlipSide
//
//  Displays detailed information about a selected Discogs release
//

import SwiftUI

struct DetailView: View {
    let match: DiscogsMatch
    
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
                
                // Pricing information
                if match.lowestPrice != nil || match.medianPrice != nil {
                    pricingSection
                }
                
                // View on Discogs button
                viewOnDiscogsButton
            }
            .padding(.vertical)
        }
        .navigationTitle("Release Details")
        .navigationBarTitleDisplayMode(.inline)
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
            
            // Metadata (Year, Label, Catalog Number)
            VStack(alignment: .leading, spacing: 8) {
                if let year = match.year {
                    metadataRow(
                        icon: "calendar",
                        label: "Year",
                        value: "\(year)"
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
                label: "Columbia",
                catalogNumber: "CL 1355",
                matchScore: 0.95,
                imageUrl: URL(string: "https://example.com/image.jpg"),
                genres: ["Jazz", "Cool Jazz", "Modal"],
                lowestPrice: 24.99,
                medianPrice: 35.00
            )
        )
    }
}
