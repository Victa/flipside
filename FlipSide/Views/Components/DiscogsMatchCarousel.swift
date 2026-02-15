//
//  DiscogsMatchCarousel.swift
//  FlipSide
//
//  Horizontal scrollable carousel of Discogs match cards
//

import SwiftUI

struct DiscogsMatchCarousel: View {
    let matches: [DiscogsMatch]
    let onMatchSelected: (DiscogsMatch, Int) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(matches.enumerated()), id: \.element.releaseId) { index, match in
                    DiscogsMatchCard(match: match, rank: index + 1)
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
                imageUrl: nil,
                genres: ["Jazz", "Cool Jazz"],
                lowestPrice: 19.99,
                medianPrice: 30.00
            ),
            DiscogsMatch(
                releaseId: 123458,
                title: "Kind of Blue (2020 Remaster)",
                artist: "Miles Davis",
                year: 2020,
                label: "Columbia",
                catalogNumber: "COL2020",
                matchScore: 0.78,
                imageUrl: URL(string: "https://i.discogs.com/example2.jpg"),
                genres: ["Jazz", "Cool Jazz", "Modal", "Bebop"],
                lowestPrice: 35.00,
                medianPrice: 50.00
            )
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
            DiscogsMatch(
                releaseId: 999999,
                title: "Blue Train",
                artist: "John Coltrane",
                year: 1957,
                label: "Blue Note",
                catalogNumber: "BLP 1577",
                matchScore: 0.92,
                imageUrl: URL(string: "https://i.discogs.com/example.jpg"),
                genres: ["Jazz", "Hard Bop"],
                lowestPrice: 150.00,
                medianPrice: 250.00
            )
        ],
        onMatchSelected: { match, index in
            print("Selected match #\(index + 1): \(match.title)")
        }
    )
    .background(Color(.systemGroupedBackground))
}
