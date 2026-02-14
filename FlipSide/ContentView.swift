//
//  ContentView.swift
//  FlipSide
//
//  Created on 2/14/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        HistoryView()
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Scan.timestamp, order: .reverse) private var scans: [Scan]
    
    @State private var showingImageCapture = false
    @State private var showingSettings = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isAPIKeyConfigured: Bool = false
    @State private var navigationPath = NavigationPath()
    @State private var isProcessing = false
    @State private var currentImage: UIImage?
    @State private var currentExtractedData: ExtractedData?
    
    // Services
    private let keychainService = KeychainService.shared
    private let persistenceService = PersistenceService.shared
    
    // Helper function to check and update API key status
    private func updateAPIKeyStatus() {
        // Only OpenAI API key is required (Discogs is optional)
        isAPIKeyConfigured = keychainService.openAIAPIKey != nil
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // Main content area
                if scans.isEmpty {
                    emptyStateView
                } else {
                    imageListView
                }
                
                // Floating Action Button (FAB)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            showingImageCapture = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .disabled(!isAPIKeyConfigured || isProcessing)
                        .opacity(isAPIKeyConfigured && !isProcessing ? 1.0 : 0.5)
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Flip Side")
            .navigationDestination(for: ProcessingDestination.self) { destination in
                ProcessingView(image: destination.image)
                    .task {
                        await performExtraction(image: destination.image)
                    }
            }
            .navigationDestination(for: ResultDestination.self) { destination in
                ResultView(
                    image: destination.image,
                    extractedData: destination.extractedData,
                    discogsMatches: destination.discogsMatches,
                    discogsError: destination.discogsError
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "gearshape")
                            
                            // Red dot badge when API keys are not configured
                            if !isAPIKeyConfigured {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingImageCapture) {
                ImageCaptureSheet { image in
                    handleImageCaptured(image)
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                // Re-check API key status when settings sheet is dismissed
                // This ensures the badge and FAB state update after API keys are configured
                updateAPIKeyStatus()
            }) {
                SettingsView()
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertMessage.contains("Error") ? "Error" : "Success"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        // If there was an error, go back to history
                        if alertMessage.contains("Error") {
                            navigationPath.removeLast(navigationPath.count)
                        }
                    }
                )
            }
            .onAppear {
                updateAPIKeyStatus()
                checkFirstRun()
            }
        }
    }
    
    // MARK: - First Run Check
    
    private func checkFirstRun() {
        // Check if OpenAI API key is configured (required)
        if keychainService.openAIAPIKey == nil {
            showingSettings = true
        }
    }
    
    private var emptyStateView: some View {
        VStack {
            Text("History View")
                .font(.largeTitle)
            Text("Past scans will appear here...")
                .foregroundStyle(.secondary)
        }
    }
    
    private var imageListView: some View {
        List {
            ForEach(scans) { scan in
                Button {
                    openScan(scan)
                } label: {
                    HStack {
                        if let image = persistenceService.loadImage(from: scan.imagePath) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            // Primary text: Discogs match title or extracted data
                            if let firstMatch = scan.discogsMatches.first {
                                Text(firstMatch.title)
                                    .font(.headline)
                                    .lineLimit(2)
                            } else if let extractedData = scan.extractedData {
                                if let artist = extractedData.artist, let album = extractedData.album {
                                    Text("\(artist) - \(album)")
                                        .font(.headline)
                                        .lineLimit(2)
                                } else if let artist = extractedData.artist {
                                    Text(artist)
                                        .font(.headline)
                                        .lineLimit(2)
                                } else if let album = extractedData.album {
                                    Text(album)
                                        .font(.headline)
                                        .lineLimit(2)
                                } else {
                                    Text("Unknown Record")
                                        .font(.headline)
                                }
                            } else {
                                Text("Unknown Record")
                                    .font(.headline)
                            }
                            
                            // Secondary text: Label and catalog number
                            if let firstMatch = scan.discogsMatches.first {
                                let labelInfo = [firstMatch.label, firstMatch.catalogNumber]
                                    .compactMap { $0 }
                                    .joined(separator: " • ")
                                if !labelInfo.isEmpty {
                                    Text(labelInfo)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            } else if let extractedData = scan.extractedData {
                                let labelInfo = [extractedData.label, extractedData.catalogNumber]
                                    .compactMap { $0 }
                                    .joined(separator: " • ")
                                if !labelInfo.isEmpty {
                                    Text(labelInfo)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteScans)
        }
    }
    
    private func handleImageCaptured(_ image: UIImage) {
        // Navigate to processing view
        currentImage = image
        navigationPath.append(ProcessingDestination(image: image))
    }
    
    private func performExtraction(image: UIImage) async {
        isProcessing = true
        
        do {
            // Call VisionService to extract vinyl info
            var extractedData = try await VisionService.shared.extractVinylInfo(from: image)
            
            // Sanitize extracted data: convert string "null" to actual nil
            extractedData = ExtractedData(
                artist: extractedData.artist?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true || extractedData.artist?.lowercased() == "null" ? nil : extractedData.artist,
                album: extractedData.album?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true || extractedData.album?.lowercased() == "null" ? nil : extractedData.album,
                label: extractedData.label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true || extractedData.label?.lowercased() == "null" ? nil : extractedData.label,
                catalogNumber: extractedData.catalogNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true || extractedData.catalogNumber?.lowercased() == "null" ? nil : extractedData.catalogNumber,
                year: extractedData.year,
                tracks: extractedData.tracks,
                rawText: extractedData.rawText,
                confidence: extractedData.confidence
            )
            
            // Search Discogs for matches (if token is available)
            var discogsMatches: [DiscogsMatch] = []
            var discogsError: String? = nil
            if KeychainService.shared.discogsPersonalToken != nil {
                do {
                    discogsMatches = try await DiscogsService.shared.searchReleases(for: extractedData)
                } catch {
                    // Capture error message to display in UI
                    discogsError = error.localizedDescription
                    print("Discogs search failed: \(error.localizedDescription)")
                }
            } else {
                discogsError = "Discogs personal access token not configured. Add it in Settings to search for matches."
            }
            
            // Save scan to SwiftData (includes saving image to documents)
            let scan = try await persistenceService.createAndSaveScan(
                image: image,
                extractedData: extractedData,
                discogsMatches: discogsMatches,
                to: modelContext
            )
            
            await MainActor.run {
                // Navigate to result view
                navigationPath.removeLast() // Remove processing view
                navigationPath.append(ResultDestination(
                    image: image,
                    extractedData: extractedData,
                    discogsMatches: discogsMatches,
                    discogsError: discogsError
                ))
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                alertMessage = "Error: \(error.localizedDescription)"
                showAlert = true
                isProcessing = false
            }
        }
    }
    
    private func openScan(_ scan: Scan) {
        guard let image = persistenceService.loadImage(from: scan.imagePath) else {
            alertMessage = "Failed to load image for this scan"
            showAlert = true
            return
        }
        
        // Navigate to ResultView with the scan's data
        let destination = ResultDestination(
            image: image,
            extractedData: scan.extractedData ?? ExtractedData(
                artist: nil,
                album: nil,
                label: nil,
                catalogNumber: nil,
                year: nil,
                tracks: nil,
                rawText: "",
                confidence: 0.0
            ),
            discogsMatches: scan.discogsMatches,
            discogsError: scan.discogsMatches.isEmpty ? "No Discogs matches found" : nil
        )
        navigationPath.append(destination)
    }
    
    private func deleteScans(at offsets: IndexSet) {
        do {
            for index in offsets {
                let scan = scans[index]
                try persistenceService.deleteScan(scan, from: modelContext)
            }
        } catch {
            alertMessage = "Failed to delete scan: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

// MARK: - Supporting Types

// Navigation destinations
struct ProcessingDestination: Hashable {
    let id = UUID()
    let image: UIImage
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ProcessingDestination, rhs: ProcessingDestination) -> Bool {
        lhs.id == rhs.id
    }
}

struct ResultDestination: Hashable {
    let id = UUID()
    let image: UIImage
    let extractedData: ExtractedData
    let discogsMatches: [DiscogsMatch]
    let discogsError: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ResultDestination, rhs: ResultDestination) -> Bool {
        lhs.id == rhs.id
    }
}

#Preview {
    ContentView()
}
