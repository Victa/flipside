//
//  ContentView.swift
//  FlipSide
//
//  Created on 2/14/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        HistoryView()
    }
}

struct HistoryView: View {
    @State private var showingImageCapture = false
    @State private var showingSettings = false
    @State private var capturedImages: [CapturedImageInfo] = []
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isAPIKeyConfigured: Bool = false // State variable to track API key status
    @State private var navigationPath = NavigationPath()
    @State private var isProcessing = false
    @State private var currentImage: UIImage?
    @State private var currentExtractedData: ExtractedData?
    
    // KeychainService instance for first-run check
    private let keychainService = KeychainService.shared
    
    // Helper function to check and update API key status
    private func updateAPIKeyStatus() {
        // Only OpenAI API key is required (Discogs is optional)
        isAPIKeyConfigured = keychainService.openAIAPIKey != nil
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // Main content area
                if capturedImages.isEmpty {
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
            ForEach(capturedImages) { imageInfo in
                HStack {
                    if let image = loadImageFromDocuments(filename: imageInfo.filename) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    VStack(alignment: .leading) {
                        if let extractedData = imageInfo.extractedData {
                            if let artist = extractedData.artist, let album = extractedData.album {
                                Text("\(artist) - \(album)")
                                    .font(.headline)
                            } else if let artist = extractedData.artist {
                                Text(artist)
                                    .font(.headline)
                            } else if let album = extractedData.album {
                                Text(album)
                                    .font(.headline)
                            } else {
                                Text("Unknown Record")
                                    .font(.headline)
                            }
                            Text(imageInfo.timestamp, style: .date)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(imageInfo.timestamp, style: .date)
                                .font(.headline)
                            Text(imageInfo.timestamp, style: .time)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
            
            // Save image to documents
            let captureService = ImageCaptureService()
            let filename = try await captureService.saveImageToDocuments(image)
            
            await MainActor.run {
                // Add to history
                let imageInfo = CapturedImageInfo(
                    filename: filename,
                    timestamp: Date(),
                    extractedData: extractedData
                )
                capturedImages.insert(imageInfo, at: 0)
                
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
    
    private func loadImageFromDocuments(filename: String) -> UIImage? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = documentsURL.appendingPathComponent(filename)
        guard let imageData = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        return UIImage(data: imageData)
    }
}

// MARK: - Supporting Types

struct CapturedImageInfo: Identifiable {
    let id = UUID()
    let filename: String
    let timestamp: Date
    let extractedData: ExtractedData?
}

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
