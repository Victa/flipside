//
//  ImageCaptureSheet.swift
//  FlipSide
//
//  Created on 2/14/26.
//

import SwiftUI
import AVFoundation

/// Modal sheet for capturing or selecting images
struct ImageCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var captureService = ImageCaptureService()
    
    @State private var captureMode: CaptureMode = .selection
    @State private var capturedImage: UIImage?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var captureSession: AVCaptureSession?
    
    let onImageCaptured: (UIImage) -> Void
    
    enum CaptureMode {
        case selection
        case camera
        case photoLibrary
    }
    
    var body: some View {
        NavigationStack {
            Group {
                switch captureMode {
                case .selection:
                    selectionView
                case .camera:
                    cameraView
                case .photoLibrary:
                    photoLibraryView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cleanup()
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
                if captureService.authorizationError == .cameraAccessDenied ||
                   captureService.authorizationError == .photoLibraryAccessDenied {
                    Button("Open Settings") {
                        openSettings()
                    }
                }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Selection View
    
    private var selectionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    startCameraCapture()
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                        Text("Take Photo")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                
                Button {
                    captureMode = .photoLibrary
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                        Text("Choose from Library")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.2))
                    .foregroundStyle(.primary)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    // MARK: - Camera View
    
    private var cameraView: some View {
        ZStack {
            // Camera preview
            if let session = captureSession {
                CameraPreviewView(session: session)
                    .ignoresSafeArea()
            } else {
                ProgressView("Starting camera...")
            }
            
            // Camera controls overlay
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    
                    // Capture button
                    Button {
                        capturePhoto()
                    } label: {
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                            .background(Circle().fill(.white.opacity(0.3)))
                            .frame(width: 70, height: 70)
                    }
                    .disabled(captureSession == nil)
                    
                    Spacer()
                }
                .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Photo Library View
    
    private var photoLibraryView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            
            Text("Select a photo from your library")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            PhotoLibraryPicker(selectedImage: $capturedImage) { image in
                handleImageSelected(image)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var navigationTitle: String {
        switch captureMode {
        case .selection:
            return "Add Image"
        case .camera:
            return "Take Photo"
        case .photoLibrary:
            return "Choose Photo"
        }
    }
    
    // MARK: - Actions
    
    private func startCameraCapture() {
        Task {
            do {
                let session = try await captureService.setupCaptureSession()
                await MainActor.run {
                    self.captureSession = session
                    self.captureMode = .camera
                }
            } catch let error as ImageCaptureService.ImageCaptureError {
                await MainActor.run {
                    errorMessage = error.localizedDescription ?? "Failed to start camera"
                    showError = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to start camera"
                    showError = true
                }
            }
        }
    }
    
    private func capturePhoto() {
        captureService.capturePhoto { result in
            switch result {
            case .success(let image):
                handleImageSelected(image)
            case .failure(let error):
                errorMessage = error.localizedDescription ?? "Failed to capture photo"
                showError = true
            }
        }
    }
    
    private func handleImageSelected(_ image: UIImage) {
        // Stop camera session before dismissing
        cleanup()
        
        // Call completion handler and dismiss
        onImageCaptured(image)
        dismiss()
    }
    
    private func cleanup() {
        captureService.stopCaptureSession()
        captureSession = nil
    }
    
    private func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}

#Preview {
    ImageCaptureSheet { image in
        print("Image captured: \(image.size)")
    }
}
