//
//  DiscogsMatchCard.swift
//  FlipSide
//
//  Reusable card component for displaying Discogs match results
//

import SwiftUI

struct DiscogsMatchCard: View {
    let match: DiscogsMatch
    let rank: Int
    var collectionStatus: (isInCollection: Bool?, isInWantlist: Bool?)? = nil
    
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
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Artwork unavailable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No artwork available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
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
                
                // Collection status labels
                if let status = collectionStatus {
                    VStack(alignment: .leading, spacing: 4) {
                        if status.isInCollection == true {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                Text("In your Collection")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.green)
                            }
                        }
                        if status.isInWantlist == true {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.caption)
                                    .foregroundStyle(.pink)
                                Text("In Your Wantlist")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.pink)
                            }
                        }
                    }
                    .padding(.top, 2)
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
                // Show the lowest available price from any condition
                if let conditionPrices = match.conditionPrices,
                   let lowestPrice = conditionPrices.values.map({ $0.value }).min() {
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

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            // Card with both collection and wantlist status
            DiscogsMatchCard(
                match: .sample(releaseId: 123456, title: "Kind of Blue", year: 1959, matchScore: 0.95),
                rank: 1,
                collectionStatus: (isInCollection: true, isInWantlist: true)
            )
            .padding()
            
            // Card with only collection status
            DiscogsMatchCard(
                match: .sample(releaseId: 123457, title: "Kind of Blue (Reissue)", year: 1997, matchScore: 0.82),
                rank: 2,
                collectionStatus: (isInCollection: true, isInWantlist: false)
            )
            .padding()
            
            // Card with only wantlist status
            DiscogsMatchCard(
                match: .sample(releaseId: 123458, title: "Blue Train", artist: "John Coltrane", year: 1957, matchScore: 0.88),
                rank: 3,
                collectionStatus: (isInCollection: false, isInWantlist: true)
            )
            .padding()
            
            // Card with no collection status
            DiscogsMatchCard(
                match: .sample(releaseId: 123459, title: "A Love Supreme", artist: "John Coltrane", year: 1965, matchScore: 0.75),
                rank: 4,
                collectionStatus: nil
            )
            .padding()
        }
    }
    .background(Color(.systemGroupedBackground))
}
