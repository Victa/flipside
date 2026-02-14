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
    
    var body: some View {
        NavigationStack {
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
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Flip Side")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingImageCapture) {
                ImageCaptureSheet { image in
                    handleImageCaptured(image)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .alert("Success", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
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
    
    private func handleImageCaptured(_ image: UIImage) {
        Task {
            do {
                let captureService = ImageCaptureService()
                let filename = try await captureService.saveImageToDocuments(image)
                
                await MainActor.run {
                    let imageInfo = CapturedImageInfo(
                        filename: filename,
                        timestamp: Date()
                    )
                    capturedImages.insert(imageInfo, at: 0)
                    alertMessage = "Image saved successfully!"
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Failed to save image: \(error.localizedDescription)"
                    showAlert = true
                }
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
}

#Preview {
    ContentView()
}
