# Flip Side

**Identify and discover your vinyl records with AI-powered scanning**

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)](https://developer.apple.com/ios/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-5.0-blue.svg)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Flip Side is a native iOS app that helps you identify and learn about your vinyl records. Simply take a photo of a record cover or label, and the app uses AI vision to extract metadata, match it with Discogs, and provide detailed release information.

> **Note**: This is a work-in-progress personal project for personal use. The app is under active development and may have incomplete features or bugs.

## Features

- **Camera & Gallery Support** - Capture photos directly or select from your photo library
- **AI-Powered Extraction** - Uses OpenAI GPT-4o-mini Vision API to extract artist, album, label, catalog number, year, and track listings
- **Discogs Integration** - Automatically matches your records with Discogs database and shows top matches with confidence scores
- **Detailed Release Info** - View complete release details including artwork, track listings, pricing, genres, and more
- **Offline History** - All scans are saved locally using SwiftData for offline viewing
- **Secure Storage** - API keys and tokens stored securely in iOS Keychain
- **Native iOS Design** - Built with SwiftUI using system components and native iOS patterns

## Architecture

Flip Side follows a clean MVVM architecture with clear separation of concerns:

```
┌──────────────────────────────────────────────┐
│            SwiftUI Views (UI Layer)          │
│  HistoryView, DetailView, SettingsView       │
└──────────────┬───────────────────────────────┘
               │
┌──────────────▼───────────────────────────────┐
│          ViewModels (MVVM Pattern)           │
└─────┬──────────┬───────────┬─────────────────┘
      │          │           │
┌─────▼──────┐  ┌───▼─────┐ ┌──▼───────────┐
│   Image    │  │ Vision  │ │   Discogs    │
│  Capture   │  │ Service │ │   Service    │
│  Service   │  │(GPT-4o  │ │   (API)      │
│ (Camera +  │  │  -mini) │ │              │
│  Gallery)  │  └─────────┘ └──────────────┘
└────────────┘
                │
         ┌──────▼─────────┐
         │ Persistence    │  ┌────────────────┐
         │ Layer          │  │ KeychainService│
         │ (SwiftData)    │  │ (API keys,     │
         └────────────────┘  │  OAuth tokens) │
                             └────────────────┘
```

## Tech Stack

- **Language**: Swift 5.9
- **UI Framework**: SwiftUI
- **Data Persistence**: SwiftData
- **Minimum iOS Version**: iOS 17.0
- **Architecture**: MVVM
- **APIs**: 
  - OpenAI GPT-4o-mini Vision API
  - Discogs API
- **Build System**: Xcode + XcodeGen

## Requirements

- iOS 17.0 or later
- Xcode 15.0 or later
- Swift 5.9
- OpenAI API key
- Discogs Personal Access Token (optional, but recommended for higher rate limits)

## Getting Started

### Prerequisites

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/flip-side.git
   cd flip-side
   ```

2. **Install dependencies**
   - This project uses XcodeGen. If you don't have it installed:
     ```bash
     brew install xcodegen
     ```
   - Generate the Xcode project:
     ```bash
     xcodegen generate
     ```

3. **Get API Keys**
   - **OpenAI API Key**: Sign up at [OpenAI](https://platform.openai.com/) and create an API key
   - **Discogs Personal Access Token** (optional): Create one at [Discogs Settings](https://www.discogs.com/settings/developers)

### Building the App

The project includes a convenient build script:

```bash
# Build and launch in simulator
./build.sh run

# Build for simulator without launching
./build.sh simulator

# Clean build artifacts
./build.sh clean

# Run tests
./build.sh test
```

Or use Xcode directly:
1. Open `FlipSide.xcodeproj`
2. Select a simulator (iPhone 17 Pro recommended)
3. Press `Cmd + R` to build and run

### First Run Setup

1. Launch the app
2. If no API keys are configured, you'll be prompted to enter them
3. Go to Settings (gear icon) and enter:
   - Your OpenAI API key
   - Your Discogs Personal Access Token (optional)
4. API keys are stored securely in iOS Keychain

## Usage

1. **Scan a Record**
   - Tap the floating action button (FAB) in the bottom-right corner
   - Choose to capture a photo or select from gallery
   - Take/select a photo of your vinyl record cover or label

2. **View Results**
   - The app processes the image using AI vision
   - Matches are found in the Discogs database
   - Browse matches in a horizontal carousel
   - Tap a match to view detailed release information

3. **View Details**
   - See complete release information including artwork, track listing, pricing, and genres
   - Tap "View on Discogs" to open the release page in Safari
   - All scans are saved to your history for offline viewing

## Security & Privacy

- **API Keys**: Stored securely in iOS Keychain
- **Local Storage**: Images and scan data stored locally only
- **No Tracking**: No analytics or user tracking
- **No Cloud Sync**: All data stays on your device (except optional Discogs OAuth)

## Project Status

### Completed Milestones

- **Milestone 1**: Image Capture Foundation
- **Milestone 2**: Vision Integration
- **Milestone 3**: Discogs Matching
- **Milestone 4**: Persistence & History
- **Milestone 4.5**: Post-Scan Flow Refactor

### In Progress

- **Milestone 5**: UI Polish

### Planned

- **Milestone 6**: Testing & Refinement
- **Milestone 7**: Discogs Link Integration
- **Milestone 8**: Social Context Integration (YouTube, Reddit)
- **Milestone 9**: Discogs Account Integration (Collection Management)

See [Plan.md](Plan.md) for detailed milestone breakdown.

## Development

### Project Structure

```
FlipSide/
├── Models/
│   └── Scan.swift              # SwiftData model for scan history
├── Services/
│   ├── VisionService.swift     # OpenAI Vision API client
│   ├── DiscogsService.swift    # Discogs API client
│   ├── ImageCaptureService.swift # Camera & gallery handling
│   ├── KeychainService.swift   # Secure key storage
│   └── PersistenceService.swift # SwiftData management
├── Views/
│   ├── ContentView.swift       # Main navigation & HistoryView
│   ├── DetailView.swift        # Release detail view
│   ├── ResultView.swift        # Match selection view
│   ├── ProcessingView.swift    # Loading states
│   ├── SettingsView.swift      # API key management
│   └── Components/            # Reusable UI components
└── FlipSideApp.swift          # App entry point
```

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftUI best practices
- Prefer composition over inheritance
- Keep views focused and reusable

## API Costs

**Estimated costs per scan:**
- OpenAI Vision API: ~$0.002-0.005 per scan
- Discogs API: Free (with personal access token)

**Note**: Costs are minimal and only occur when scanning new records. Viewing saved scans is completely free.

## Contributing

This is currently a personal project, but contributions are welcome! Please feel free to open issues or submit pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Discogs](https://www.discogs.com/) for the comprehensive vinyl database
- [OpenAI](https://openai.com/) for the powerful vision API
- Built with SwiftUI for iOS

---

Made with SwiftUI for iOS
