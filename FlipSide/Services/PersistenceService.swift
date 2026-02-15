//
//  PersistenceService.swift
//  FlipSide
//
//  Created on 2/14/26.
//

import Foundation
import UIKit
import SwiftData

class PersistenceService {
    static let shared = PersistenceService()
    
    private init() {}
    
    // MARK: - Image Storage
    
    /// Save an image to the app's documents directory and return the file path
    private func saveImage(_ image: UIImage) throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw PersistenceError.imageConversionFailed
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = documentsDirectory.appendingPathComponent(filename)
        
        try imageData.write(to: fileURL)
        return filename
    }
    
    /// Load an image from the app's documents directory given a filename
    func loadImage(from filename: String) -> UIImage? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsDirectory.appendingPathComponent(filename)
        
        guard let imageData = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        return UIImage(data: imageData)
    }
    
    /// Delete an image file from the app's documents directory
    private func deleteImage(at filename: String) throws {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsDirectory.appendingPathComponent(filename)
        
        try FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Scan Management
    
    /// Create and save a new scan to SwiftData
    func createAndSaveScan(
        image: UIImage,
        extractedData: ExtractedData?,
        discogsMatches: [DiscogsMatch],
        to modelContext: ModelContext
    ) async throws -> Scan {
        // Save image to disk
        let imagePath = try saveImage(image)
        
        // Create scan object
        let scan = Scan(
            id: UUID(),
            imagePath: imagePath,
            timestamp: Date(),
            extractedData: extractedData,
            discogsMatches: discogsMatches,
            selectedMatchIndex: nil
        )
        
        // Save to SwiftData
        modelContext.insert(scan)
        try modelContext.save()
        
        return scan
    }
    
    /// Delete a scan and its associated image file
    func deleteScan(_ scan: Scan, from modelContext: ModelContext) throws {
        // Delete image file
        try? deleteImage(at: scan.imagePath)
        
        // Delete from SwiftData
        modelContext.delete(scan)
        try modelContext.save()
    }
}

// MARK: - Errors

enum PersistenceError: LocalizedError {
    case imageConversionFailed
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to JPEG format"
        case .fileNotFound:
            return "Image file not found"
        }
    }
}
