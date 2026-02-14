//
//  ImageCaptureService.swift
//  FlipSide
//
//  Created on 2/14/26.
//

import SwiftUI
import AVFoundation
import PhotosUI

/// Service for capturing images from camera or photo library
class ImageCaptureService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var capturedImage: UIImage?
    @Published var isAuthorized = false
    @Published var authorizationError: ImageCaptureError?
    
    // MARK: - Private Properties
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCapturePhotoOutput?
    private var currentPhotoDelegate: PhotoCaptureDelegate?
    
    // MARK: - Types
    
    enum ImageCaptureError: LocalizedError {
        case cameraUnavailable
        case cameraAccessDenied
        case photoLibraryAccessDenied
        case captureSessionSetupFailed
        case photoCaptureFailed
        case imageProcessingFailed
        case saveFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .cameraUnavailable:
                return "Camera is not available on this device"
            case .cameraAccessDenied:
                return "Camera access denied. Please enable in Settings."
            case .photoLibraryAccessDenied:
                return "Photo library access denied. Please enable in Settings."
            case .captureSessionSetupFailed:
                return "Failed to setup camera"
            case .photoCaptureFailed:
                return "Failed to capture photo"
            case .imageProcessingFailed:
                return "Failed to process image"
            case .saveFailed(let error):
                return "Failed to save image: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - Camera Authorization
    
    func checkCameraAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await MainActor.run { isAuthorized = true }
            return true
        case .notDetermined:
            return await requestCameraAccess()
        case .denied, .restricted:
            await MainActor.run {
                authorizationError = .cameraAccessDenied
                isAuthorized = false
            }
            return false
        @unknown default:
            await MainActor.run { isAuthorized = false }
            return false
        }
    }
    
    private func requestCameraAccess() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run { isAuthorized = granted }
        if !granted {
            await MainActor.run { authorizationError = .cameraAccessDenied }
        }
        return granted
    }
    
    // MARK: - Camera Setup
    
    func setupCaptureSession() async throws -> AVCaptureSession {
        guard await checkCameraAuthorization() else {
            throw ImageCaptureError.cameraAccessDenied
        }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        // Configure session preset for high quality photos
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }
        
        // Get camera device
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw ImageCaptureError.cameraUnavailable
        }
        
        // Create and add video input
        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            throw ImageCaptureError.captureSessionSetupFailed
        }
        session.addInput(videoInput)
        
        // Create and add photo output
        let photoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(photoOutput) else {
            throw ImageCaptureError.captureSessionSetupFailed
        }
        session.addOutput(photoOutput)
        
        session.commitConfiguration()
        
        self.captureSession = session
        self.videoOutput = photoOutput
        
        return session
    }
    
    // MARK: - Photo Capture
    
    func capturePhoto(completion: @escaping (Result<UIImage, ImageCaptureError>) -> Void) {
        guard let photoOutput = videoOutput else {
            completion(.failure(.captureSessionSetupFailed))
            return
        }
        
        let photoSettings = AVCapturePhotoSettings()
        
        // Configure photo settings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            photoSettings.photoCodecType = .hevc
        }
        
        // Enable high quality photo
        photoSettings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        
        // Create delegate to handle capture
        let delegate = PhotoCaptureDelegate { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
        
        self.currentPhotoDelegate = delegate
        photoOutput.capturePhoto(with: photoSettings, delegate: delegate)
    }
    
    // MARK: - Image Saving
    
    func saveImageToDocuments(_ image: UIImage, filename: String? = nil) async throws -> String {
        // Optimize image for storage (resize if needed, compress as JPEG)
        guard let optimizedImage = optimizeImageForStorage(image) else {
            throw ImageCaptureError.imageProcessingFailed
        }
        
        guard let imageData = optimizedImage.jpegData(compressionQuality: 0.85) else {
            throw ImageCaptureError.imageProcessingFailed
        }
        
        // Generate filename
        let fileName = filename ?? "\(UUID().uuidString).jpg"
        
        // Get documents directory
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ImageCaptureError.imageProcessingFailed
        }
        
        let fileURL = documentsURL.appendingPathComponent(fileName)
        
        // Save image data
        do {
            try imageData.write(to: fileURL)
            return fileName // Return relative path for storage in SwiftData
        } catch {
            throw ImageCaptureError.saveFailed(error)
        }
    }
    
    // MARK: - Image Optimization
    
    private func optimizeImageForStorage(_ image: UIImage) -> UIImage? {
        let maxDimension: CGFloat = 2048
        let size = image.size
        
        // Check if resizing is needed
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        // Calculate new size maintaining aspect ratio
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        // Resize image
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // MARK: - Cleanup
    
    func stopCaptureSession() {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
    }
}

// MARK: - Photo Capture Delegate

private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<UIImage, ImageCaptureService.ImageCaptureError>) -> Void
    
    init(completion: @escaping (Result<UIImage, ImageCaptureService.ImageCaptureError>) -> Void) {
        self.completion = completion
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error.localizedDescription)")
            completion(.failure(.photoCaptureFailed))
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            completion(.failure(.imageProcessingFailed))
            return
        }
        
        completion(.success(image))
    }
}
