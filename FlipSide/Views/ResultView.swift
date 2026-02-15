//
//  ResultView.swift
//  FlipSide
//
//  Match selection view with horizontal carousel of Discogs matches
//

import SwiftUI

struct ResultView: View {
    let image: UIImage
    let extractedData: ExtractedData
    let discogsMatches: [DiscogsMatch]
    let discogsError: String?
    let onMatchSelected: (DiscogsMatch, Int) -> Void
    
    @StateObject private var networkMonitor = NetworkMonitor.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Offline indicator banner
                if !networkMonitor.isConnected {
                    offlineIndicatorBanner
                }
                
                // Captured image (smaller for carousel focus)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
                    .padding(.horizontal)
                
                // Match selection section
                matchSelectionSection
            }
            .padding(.vertical)
        }
        .navigationTitle("Select Match")
        .navigationBarTitleDisplayMode(.inline)
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
                    Text("\(discogsMatches.prefix(5).count) \(discogsMatches.count == 1 ? "match" : "matches")")
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
                        matches: Array(discogsMatches.prefix(5)),
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
            discogsError: nil,
            onMatchSelected: { match, index in
                print("Preview: Selected \(match.title) at index \(index)")
            }
        )
    }
}
