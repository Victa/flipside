//
//  DiscogsMatchCarousel.swift
//  FlipSide
//
//  Horizontal scrollable carousel of Discogs match cards
//

import SwiftUI

struct DiscogsMatchCarousel: View {
    let matches: [DiscogsMatch]
    var collectionStatus: (isInCollection: Bool?, isInWantlist: Bool?)? = nil
    let onMatchSelected: (DiscogsMatch, Int) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(matches.enumerated()), id: \.element.releaseId) { index, match in
                    DiscogsMatchCard(
                        match: match,
                        rank: index + 1,
                        collectionStatus: collectionStatus
                    )
                    .frame(width: 280)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onMatchSelected(match, index)
                    }
                    .scaleEffect(1.0) // Enables tap animation
                    .animation(.easeInOut(duration: 0.1), value: false)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Preview

#Preview("Multiple Matches") {
    DiscogsMatchCarousel(
        matches: [
            .sample(releaseId: 123456, title: "Kind of Blue", year: 1959, matchScore: 0.95),
            .sample(releaseId: 123457, title: "Kind of Blue (Reissue)", year: 1997, matchScore: 0.82),
            .sample(releaseId: 123458, title: "Kind of Blue (2020 Remaster)", year: 2020, matchScore: 0.78)
        ],
        onMatchSelected: { match, index in
            print("Selected match #\(index + 1): \(match.title)")
        }
    )
    .background(Color(.systemGroupedBackground))
}

#Preview("Single Match") {
    DiscogsMatchCarousel(
        matches: [
            .sample(releaseId: 999999, title: "Blue Train", artist: "John Coltrane", year: 1957, matchScore: 0.92)
        ],
        onMatchSelected: { match, index in
            print("Selected match #\(index + 1): \(match.title)")
        }
    )
    .background(Color(.systemGroupedBackground))
}
