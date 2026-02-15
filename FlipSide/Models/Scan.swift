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

struct DiscogsMatch: Codable, Equatable {
    // Basic info
    var releaseId: Int
    var title: String
    var artist: String
    var year: Int?
    var released: String? // Full release date (e.g., "1995-03-15")
    var country: String?
    var label: String?
    var catalogNumber: String?
    var matchScore: Double
    
    // Images
    var imageUrl: URL?
    var thumbnailUrl: URL?
    
    // Classification
    var genres: [String]
    var styles: [String] // More specific than genres (e.g., "Dub", "Roots Reggae")
    
    // Formats (vinyl size, speed, etc.)
    var formats: [Format]
    
    // Tracklist
    var tracklist: [TracklistItem]
    
    // Identifiers (barcodes, matrix numbers)
    var identifiers: [Identifier]
    
    // Pricing
    var lowestPrice: Decimal?
    var medianPrice: Decimal?
    var highPrice: Decimal?
    
    // Community stats
    var numForSale: Int? // Number of copies available for sale
    var inWantlist: Int? // Number of users who want this
    var inCollection: Int? // Number of users who have this
    
    // Additional info
    var notes: String? // Release notes/description
    var dataQuality: String? // "Correct", "Complete and Correct", etc.
    var masterId: Int? // Master release ID for grouping pressings
    var uri: String? // Discogs URI path
    var resourceUrl: String? // API resource URL
    var videos: [Video] // YouTube and other video links
    
    struct Format: Codable, Equatable {
        var name: String // "Vinyl", "CD", etc.
        var qty: String? // Quantity
        var descriptions: [String]? // "7\"", "12\"", "LP", "Single", "45 RPM", etc.
        var text: String? // Additional format text
    }
    
    struct TracklistItem: Codable, Equatable {
        var position: String // "A1", "B2", "1", etc.
        var title: String
        var duration: String? // "3:45"
        var artists: [TrackArtist]?
        var extraartists: [TrackArtist]? // Featured artists, producers, etc.
        
        struct TrackArtist: Codable, Equatable {
            var name: String
            var role: String? // "Vocals", "Producer", etc.
        }
    }
    
    struct Identifier: Codable, Equatable {
        var type: String // "Barcode", "Matrix / Runout", "Label Code", etc.
        var value: String
        var description: String?
    }
    
    struct Video: Codable, Equatable {
        var uri: String // YouTube URL
        var title: String
        var description: String?
        var duration: Int? // Duration in seconds
    }
    
    // MARK: - Preview Helper
    
    #if DEBUG
    static func sample(
        releaseId: Int = 123456,
        title: String = "Kind of Blue",
        artist: String = "Miles Davis",
        year: Int? = 1959,
        matchScore: Double = 0.95,
        genres: [String] = ["Jazz"],
        lowestPrice: Decimal? = 24.99,
        medianPrice: Decimal? = 35.00,
        highPrice: Decimal? = 75.00
    ) -> DiscogsMatch {
        return DiscogsMatch(
            releaseId: releaseId,
            title: title,
            artist: artist,
            year: year,
            released: nil,
            country: nil,
            label: "Columbia",
            catalogNumber: "CL 1355",
            matchScore: matchScore,
            imageUrl: nil,
            thumbnailUrl: nil,
            genres: genres,
            styles: [],
            formats: [],
            tracklist: [],
            identifiers: [],
            lowestPrice: lowestPrice,
            medianPrice: medianPrice,
            highPrice: highPrice,
            numForSale: nil,
            inWantlist: nil,
            inCollection: nil,
            notes: nil,
            dataQuality: nil,
            masterId: nil,
            uri: nil,
            resourceUrl: nil,
            videos: []
        )
    }
    #endif
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
