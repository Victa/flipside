# DiscogsService Usage Guide

## Overview

The `DiscogsService` is a complete API client for searching and fetching vinyl release information from the Discogs database. It implements intelligent matching algorithms, rate limiting, and error handling.

## Features

✅ **Search releases** using extracted vinyl data (artist, album, label, catalog number)  
✅ **Match scoring algorithm** with weighted field comparison (fuzzy matching)  
✅ **Rate limiting** (60 requests/minute with personal access token)  
✅ **Retry logic** with exponential backoff for rate limits  
✅ **Fetch detailed release information** including pricing data  
✅ **Generate Discogs URLs** for viewing releases on the website  

## Prerequisites

Before using DiscogsService, ensure you have:

1. A Discogs personal access token stored in Keychain
2. The token can be obtained from: https://www.discogs.com/settings/developers

```swift
// Store the token (usually done in SettingsView)
try KeychainService.shared.setDiscogsPersonalToken("your_token_here")
```

## Basic Usage

### 1. Search for Releases

```swift
import Foundation

// Assuming you have extracted data from a vinyl image
let extractedData = ExtractedData(
    artist: "Pink Floyd",
    album: "The Dark Side of the Moon",
    label: "Harvest",
    catalogNumber: "SHVL 804",
    year: 1973,
    rawText: "...",
    confidence: 0.85
)

// Search for matches
do {
    let matches = try await DiscogsService.shared.searchReleases(for: extractedData)
    
    // Matches are sorted by match score (highest first)
    for match in matches {
        print("Title: \(match.title)")
        print("Artist: \(match.artist)")
        print("Match Score: \(match.matchScore)")
        print("---")
    }
} catch {
    print("Search failed: \(error.localizedDescription)")
}
```

### 2. Search and Fetch Detailed Information

For the top matches, you can fetch additional details including pricing:

```swift
do {
    // This fetches details for the top 3 matches automatically
    let detailedMatches = try await DiscogsService.shared.searchAndFetchDetails(for: extractedData)
    
    for match in detailedMatches {
        print("Title: \(match.title)")
        print("Genres: \(match.genres.joined(separator: ", "))")
        
        if let price = match.lowestPrice {
            print("Lowest Price: $\(price)")
        }
        
        if let url = DiscogsService.shared.generateReleaseURL(releaseId: match.releaseId) {
            print("View on Discogs: \(url)")
        }
        print("---")
    }
} catch {
    print("Search failed: \(error.localizedDescription)")
}
```

### 3. Generate Discogs URL

```swift
let releaseId = 249504 // Example: Pink Floyd - The Dark Side of the Moon
if let url = DiscogsService.shared.generateReleaseURL(releaseId: releaseId) {
    print("View on Discogs: \(url)")
    // Opens: https://www.discogs.com/release/249504
}
```

## Match Scoring Algorithm

The service uses a weighted scoring algorithm to rank matches:

| Field | Weight | Description |
|-------|--------|-------------|
| Artist | 30% | Fuzzy match on artist name |
| Album | 30% | Fuzzy match on album title |
| Catalog Number | 25% | Highly specific identifier |
| Label | 10% | Record label match |
| Year | 5% | Exact or close year match |

**Match Score Range:** 0.0 (no match) to 1.0 (perfect match)

### Fuzzy Matching

The service uses Levenshtein distance for string similarity:
- **1.0** = Exact match
- **0.8** = One string contains the other
- **< 0.8** = Similarity based on edit distance

## Error Handling

```swift
do {
    let matches = try await DiscogsService.shared.searchReleases(for: extractedData)
    // Process matches
} catch DiscogsService.DiscogsError.noPersonalToken {
    // Prompt user to configure token in Settings
    print("Please configure your Discogs token in Settings")
} catch DiscogsService.DiscogsError.rateLimitExceeded {
    // Wait and retry
    print("Rate limit exceeded. Please wait a moment.")
} catch DiscogsService.DiscogsError.noMatches {
    // No results found
    print("No matching releases found in Discogs database")
} catch {
    // Other errors
    print("Error: \(error.localizedDescription)")
}
```

## Rate Limiting

The service automatically handles rate limiting:
- **Personal access token:** 60 requests/minute
- **Automatic throttling:** Waits between requests if needed
- **Retry logic:** Exponential backoff for rate limit errors

## Integration Example

Here's how to integrate DiscogsService into a ViewModel:

```swift
@Observable
class ScannerViewModel {
    var matches: [DiscogsMatch] = []
    var isSearching = false
    var errorMessage: String?
    
    func searchDiscogs(for extractedData: ExtractedData) async {
        isSearching = true
        errorMessage = nil
        
        do {
            matches = try await DiscogsService.shared.searchAndFetchDetails(for: extractedData)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isSearching = false
    }
}
```

## API Response Models

### DiscogsMatch

```swift
struct DiscogsMatch: Codable {
    var releaseId: Int              // Discogs release ID
    var title: String               // Full title (Artist - Album)
    var artist: String              // Artist name
    var year: Int?                  // Release year
    var label: String?              // Record label
    var catalogNumber: String?      // Catalog number
    var matchScore: Double          // 0.0 - 1.0
    var imageUrl: URL?              // Cover image URL
    var genres: [String]            // Genre tags
    var lowestPrice: Decimal?       // Lowest marketplace price
    var medianPrice: Decimal?       // Median marketplace price
}
```

## Next Steps

After implementing DiscogsService (Milestone 3, Task 16), the next tasks are:

- **Task 17:** Implement search with extracted fields
- **Task 18:** Build match scoring algorithm (✅ Already implemented!)
- **Task 19:** Display top 3-5 matches with confidence scores

The DiscogsService is now ready to be integrated into the app's ViewModels and UI!
