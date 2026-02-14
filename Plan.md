
# Flip Side - Native iOS Architecture Plan

## Technology Decision: SwiftUI (Native)

**Rationale:**

- **iPhone-only** - No cross-platform need, React Native's main value prop doesn't apply
- **Camera integration** - AVFoundation and PHPicker are simpler and more reliable than React Native camera libraries
- **Local persistence** - SwiftData/Core Data offer seamless iOS integration
- **Performance** - Better image processing, smaller app size (~5MB vs ~50MB)
- **Cost neutral** - Both platforms call same OpenAI API (no cost difference)
- **Simplicity** - Fewer dependencies, no bridge overhead, standard iOS patterns
- **Long-term maintenance** - Native APIs evolve with iOS, no third-party library churn
- **Testing flexibility** - PHPicker allows testing with sample images without physical vinyl records

## Minimal Architecture

```
┌──────────────────────────────────────────────┐
│            SwiftUI Views (UI Layer)          │
│  HistoryView (main home page with FAB)       │
│  - ResultView, DetailView (triggers social)  │
│  - SettingsView (API keys, Discogs account)  │
└──────────────┬───────────────────────────────┘
               │
┌──────────────▼───────────────────────────────┐
│          ViewModels (MVVM Pattern)           │
│  - ScannerViewModel, ResultViewModel         │
│  - DetailViewModel (loads social async)      │
└─────┬──────────┬───────────┬─────────────────┘
      │          │           │
┌─────▼──────┐  ┌───▼─────┐ ┌──▼───────────┐
│   Image    │  │ Vision  │ │   Discogs    │
│  Capture   │  │ Service │ │   Service    │
│  Service   │  │(GPT-4o  │ │   (API)      │
│ (Camera +  │  │  -mini) │ │              │
│  Gallery)  │  └─────────┘ └──────────────┘
└────────────┘
                │              │
                │      ┌───────▼──────────────┐
                │      │ SocialContextService │
                │      │ (YouTube, Reddit)    │
                │      └───────┬──────────────┘
                │              │
                │      ┌───────▼──────────────┐
                │      │ AI Summarization     │
                │      │ (GPT-4o-mini)        │
                │      └──────────────────────┘
                │
         ┌──────▼─────────┐
         │ Persistence    │  ┌────────────────┐
         │ Layer          │  │ KeychainService│
         │ (SwiftData)    │  │ (API keys,     │
         └────────────────┘  │  OAuth tokens) │
                             └────────────────┘
```

## App Navigation Structure

- **Single main view:** HistoryView (home page) showing all past scans
- **Floating Action Button (FAB):** Bottom-right corner with options to capture photo or select from gallery
- **Navigation flow:** HistoryView (with FAB) → ProcessingView → ResultView → DetailView (via NavigationStack)
- **SettingsView:** Accessible from toolbar (gear icon) — manages OpenAI API key, Discogs personal access token, and (later) Discogs OAuth connection
- **First-run:** If no API keys are configured, present SettingsView as a sheet on launch

## Core Modules

### 1. ImageCaptureService

- Manages AVFoundation capture session for camera
- Handles PHPickerViewController for photo library selection
- Handles photo capture and image quality
- Provides camera preview
- Supports both camera capture and gallery upload

### 2. VisionService

- OpenAI GPT-4o-mini Vision API client
- Extracts: artist, album title, label, catalog number, year
- Prompt engineering for vinyl-specific OCR
- Structured JSON output parsing
- Error handling and retry logic

### 3. DiscogsService

- Discogs API client (search endpoint)
- Match scoring algorithm (fuzzy matching on extracted fields)
- Fetches release details and pricing data
- Rate limit handling:
  - Unauthenticated: 25 requests/minute
  - Personal access token (Milestones 1-7): 60 requests/minute
  - OAuth authenticated (Milestone 9): 60 requests/minute
- Generates Discogs release page URLs

### 3a. DiscogsAuthService (Milestone 9)

- Discogs OAuth 1.0a authentication flow
- Token storage and management (Keychain)
- Collection status checking
- Add to collection/wantlist operations
- Token refresh handling

### 4. PersistenceService

- SwiftData models for local storage
- Stores images as JPEG files in app Documents directory (paths stored in SwiftData)
- Manages scan history
- Enables offline viewing

### 5. KeychainService

- Wrapper around iOS Keychain for secure storage
- Stores OpenAI API key
- Stores Discogs personal access token
- Stores Discogs OAuth tokens (Milestone 9)
- Provides simple get/set/delete interface

### 6. SocialContextService (Milestone 8)

- Aggregates social content from multiple APIs
- YouTube Data API integration (reviews, reactions, discussions)
- Reddit API integration (r/vinyl, r/music, artist subreddits) — requires Reddit app registration
- Structures and ranks social insights
- Uses AI (GPT-4o-mini) to summarize findings into curated insights
- Handles rate limiting and API quotas
- Triggered on-demand when DetailView loads (not automatic)

### 7. UI Layer (SwiftUI)

- HistoryView: Main home page listing all past scans + Floating Action Button (FAB) at bottom-right for capture/upload
- ImageCaptureSheet: Modal sheet triggered by FAB with camera capture + photo library picker options
- ProcessingView: Loading states during Vision API and Discogs calls
- ResultView: Match results with confidence scores
- DetailView: Full release information + Discogs link + social context (loads on-demand with spinner, Milestone 8) + collection status/actions (Milestone 9)
- SettingsView: API key management, Discogs account connection

**Design Approach:**

- Use default iOS system styling and components
- Native NavigationStack, TabView, List, and standard controls
- System fonts, colors, and spacing
- No custom design system required

## Core Data Models

### Scan

```swift
@Model
class Scan {
    var id: UUID
    var imagePath: String     // Path to JPEG in Documents directory
    var timestamp: Date
    var extractedData: ExtractedData?
    var discogsMatches: [DiscogsMatch]
    var selectedMatchIndex: Int?
    var socialContext: SocialContext?  // Added in Milestone 8
    var isInCollection: Bool?  // Added in Milestone 9 (nil = not checked)
    var isInWantlist: Bool?   // Added in Milestone 9 (nil = not checked)
}
```

### ExtractedData

```swift
struct ExtractedData: Codable {
    var artist: String?
    var album: String?
    var label: String?
    var catalogNumber: String?
    var year: Int?
    var rawText: String
    var confidence: Double
}
```

### DiscogsMatch

```swift
struct DiscogsMatch: Codable {
    var releaseId: Int
    var title: String
    var artist: String
    var year: Int?
    var label: String?
    var catalogNumber: String?
    var matchScore: Double  // 0.0 - 1.0
    var imageUrl: URL?
    var genres: [String]
    var lowestPrice: Decimal?
    var medianPrice: Decimal?
}
```

### SocialContext (Milestone 8)

```swift
struct SocialContext: Codable {
    var youtubeVideos: [YouTubeVideo]
    var redditPosts: [RedditPost]
    var aiSummary: String  // AI-generated summary of findings
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
```

## API Cost Optimization

**OpenAI Vision Strategy:**

- Resize images to 1024x1024 max (reduces token cost)
- Use GPT-4o-mini with structured JSON output
- Estimated cost: ~$0.002-0.005 per scan
- API key stored in Keychain

**Discogs Strategy:**

- Single search call per scan (personal access token: 60/min)
- Get pricing from marketplace API
- Estimated cost: Free (with personal access token)

## Error Handling Strategy

- **Network unavailable:** Show alert with retry option; allow browsing scan history offline
- **API rate limits:** Queue requests and retry with exponential backoff
- **API errors (5xx, timeouts):** Show user-friendly error with retry button; log details for debugging
- **Invalid/missing API key:** Redirect user to SettingsView with explanation
- **No Discogs matches:** Show extracted data with "No matches found" state and option to retry or edit search
- **Vision extraction failure:** Show captured image with option to retake photo

## Security & Privacy

- API keys stored in iOS Keychain (via KeychainService)
- Discogs OAuth tokens stored securely in iOS Keychain
- Images stored locally only (never uploaded beyond API processing)
- No analytics or tracking
- No user accounts or cloud sync (except optional Discogs OAuth)
- Discogs OAuth for collection management (optional - user chooses to connect)

## Milestone-Based Build Plan

### Milestone 1: Image Capture Foundation (Week 1)

- [x] 1. Initialize Xcode project with SwiftUI + SwiftData (target: iOS 17.0)
- [x] 2. **REFACTOR:** Remove TabView structure and consolidate to single HistoryView as main screen with FAB (since two-view structure was already built in step 1)
- [ ] 3. Add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to Info.plist
- [ ] 4. Implement ImageCaptureService with AVFoundation (camera) and PHPickerViewController (photo library)
- [ ] 5. Build Floating Action Button (FAB) in HistoryView (bottom-right corner) that opens image capture options sheet
- [ ] 6. Build ImageCaptureSheet modal with camera capture + photo library picker options
- [ ] 7. Save captured/selected images to app Documents directory
- [ ] 8. Create KeychainService wrapper
- [ ] 9. Build SettingsView for API key entry (OpenAI key, Discogs token)
- [ ] 10. Add first-run check: present SettingsView if no API keys configured

### Milestone 2: Vision Integration (Week 1-2)

- [ ] 11. Create VisionService with OpenAI GPT-4o-mini API client
- [ ] 12. Implement prompt for vinyl record text extraction
- [ ] 13. Parse structured JSON response into ExtractedData
- [ ] 14. Connect API key from KeychainService
- [ ] 15. Display extracted text in UI

### Milestone 3: Discogs Matching (Week 2)

- [ ] 16. Create DiscogsService API client (using personal access token from Keychain)
- [ ] 17. Implement search with extracted fields
- [ ] 18. Build match scoring algorithm (weighted field comparison)
- [ ] 19. Display top 3-5 matches with confidence scores

### Milestone 4: Persistence (Week 2-3)

- [ ] 20. Define SwiftData models (Scan with Codable structs for ExtractedData, DiscogsMatch)
- [ ] 21. Implement save/load for scans (images stored as files, paths in SwiftData)
- [ ] 22. Build HistoryView with list of past scans
- [ ] 23. Add offline viewing for saved results

### Milestone 5: UI Polish (Week 3)

- [ ] 24. Design ResultView with match cards
- [ ] 25. Add image comparison (scanned vs Discogs)
- [ ] 26. Implement pricing display
- [ ] 27. Error states and loading indicators
- [ ] 28. Empty states for history

### Milestone 6: Testing & Refinement (Week 3-4)

- [ ] 29. Test with various vinyl types (covers, labels, different conditions)
- [ ] 30. Test with both camera capture and photo library images
- [ ] 31. Refine OCR prompts based on results
- [ ] 32. Optimize match scoring algorithm
- [ ] 33. Handle edge cases (no matches, API failures)
- [ ] 34. Performance testing

### Milestone 7: Discogs Link Integration (Week 4)

- [ ] 35. Add "View on Discogs" button/link in DetailView
- [ ] 36. Implement URL generation for Discogs release page (format: https://www.discogs.com/release/{releaseId})
- [ ] 37. Open Discogs page in Safari using SFSafariViewController or Link
- [ ] 38. Add visual indicator (SF Symbol: arrow.up.right.square or link icon)
- [ ] 39. Test link opens correct release page

### Milestone 8: Social Context Integration (Week 4-5)

- [ ] 40. Create SocialContextService for API aggregation
- [ ] 41. Integrate YouTube Data API (search for album reviews, reactions)
- [ ] 42. Integrate Reddit API (search r/vinyl, r/music, artist subreddits) — register Reddit app
- [ ] 43. Parse and structure social content (comments, video titles, upvotes)
- [ ] 44. Implement AI summarization using GPT-4o-mini (summarize findings into insights)
- [ ] 45. Add on-demand fetch when DetailView appears (not automatic)
- [ ] 46. Add loading spinner/indicator in DetailView while fetching social context
- [ ] 47. Design "Community Insights" section in DetailView
- [ ] 48. Display AI-generated summary with source links (YouTube videos, Reddit posts)
- [ ] 49. Cache social results with scan for offline viewing
- [ ] 50. Handle API rate limits gracefully
- [ ] 51. Show cached results immediately if available, refresh in background

**Cost Analysis:**

- YouTube Data API: Free tier (10,000 units/day; ~100 searches/day)
- Reddit API: Free for OAuth apps (100 requests/minute; requires app registration)
- GPT-4o-mini summarization: ~$0.001-0.005 per summary
- **Total estimated cost: ~$0.003-0.01 per detail view load** (only when user views details)

### Milestone 9: Discogs Account Integration (Week 5-6)

- [ ] 52. Implement Discogs OAuth 1.0a authentication flow
- [ ] 53. Store OAuth tokens securely in iOS Keychain
- [ ] 54. Create DiscogsAuthService for token management
- [ ] 55. Add "Connect Discogs Account" in SettingsView
- [ ] 56. Implement collection check API call (GET /users/{username}/collection/folders/{folder_id}/releases)
- [ ] 57. Display collection status in DetailView (in collection / not in collection)
- [ ] 58. Implement "Add to Collection" action using Discogs API
- [ ] 59. Implement "Add to Wantlist" action using Discogs API
- [ ] 60. Add UI buttons/actions in DetailView for collection management
- [ ] 61. Handle authentication errors and token refresh
- [ ] 62. Cache collection status locally to reduce API calls
- [ ] 63. Show loading states during collection operations

**Discogs API Endpoints:**

- OAuth: https://www.discogs.com/oauth/authorize
- Collection: GET /users/{username}/collection/folders/{folder_id}/releases
- Add to Collection: POST /users/{username}/collection/folders/{folder_id}/releases/{release_id}/instances/{instance_id}
- Wantlist: GET/POST /users/{username}/wants

**Cost Analysis:**

- Discogs API: Free for authenticated personal use
- Rate limit: 60 requests/minute
- Estimated cost: $0 (within rate limits)

## Key Dependencies

- iOS 17.0 minimum deployment target (for SwiftData)
- OpenAI Swift SDK (or direct URLSession calls)
- No third-party libraries required for core functionality

## Future Enhancements (Beyond Milestone 9)

- Batch scanning mode
- Collection export (CSV)
- Barcode scanning fallback
- Manual field editing
- Integration with other music APIs (Last.fm, Spotify for streaming links)
- Share scan results with friends
- Bulk collection operations (add multiple records at once)