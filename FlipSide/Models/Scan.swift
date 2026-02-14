//
//  Scan.swift
//  FlipSide
//
//  Created on 2/14/26.
//

import Foundation
import SwiftData

@Model
class Scan {
    var id: UUID
    var imagePath: String
    var timestamp: Date
    var extractedData: ExtractedData?
    var discogsMatches: [DiscogsMatch]
    var selectedMatchIndex: Int?
    var socialContext: SocialContext?
    var isInCollection: Bool?
    var isInWantlist: Bool?
    
    init(
        id: UUID = UUID(),
        imagePath: String,
        timestamp: Date = Date(),
        extractedData: ExtractedData? = nil,
        discogsMatches: [DiscogsMatch] = [],
        selectedMatchIndex: Int? = nil,
        socialContext: SocialContext? = nil,
        isInCollection: Bool? = nil,
        isInWantlist: Bool? = nil
    ) {
        self.id = id
        self.imagePath = imagePath
        self.timestamp = timestamp
        self.extractedData = extractedData
        self.discogsMatches = discogsMatches
        self.selectedMatchIndex = selectedMatchIndex
        self.socialContext = socialContext
        self.isInCollection = isInCollection
        self.isInWantlist = isInWantlist
    }
}

struct ExtractedData: Codable {
    var artist: String?
    var album: String?
    var label: String?
    var catalogNumber: String?
    var year: Int?
    var tracks: [Track]? // Track listing (critical for singles and EPs)
    var rawText: String
    var confidence: Double
    
    struct Track: Codable {
        var position: String // e.g., "1", "A1", "B2"
        var title: String
        var artist: String? // Optional artist credit if different from main artist
    }
}

struct DiscogsMatch: Codable {
    var releaseId: Int
    var title: String
    var artist: String
    var year: Int?
    var label: String?
    var catalogNumber: String?
    var matchScore: Double
    var imageUrl: URL?
    var genres: [String]
    var lowestPrice: Decimal?
    var medianPrice: Decimal?
}

struct SocialContext: Codable {
    var youtubeVideos: [YouTubeVideo]
    var redditPosts: [RedditPost]
    var aiSummary: String
    var fetchedAt: Date
    
    struct YouTubeVideo: Codable {
        var videoId: String
        var title: String
        var channelName: String
        var viewCount: Int
        var thumbnailUrl: URL?
    }
    
    struct RedditPost: Codable {
        var postId: String
        var title: String
        var subreddit: String
        var upvotes: Int
        var commentCount: Int
        var url: URL
    }
}
