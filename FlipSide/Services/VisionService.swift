//
//  VisionService.swift
//  FlipSide
//
//  OpenAI GPT-4o-mini Vision API client for vinyl record text extraction.
//

import Foundation
import UIKit

/// Service for extracting vinyl record information from images using OpenAI Vision API
final class VisionService {
    
    // MARK: - Configuration
    
    private let apiEndpoint = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o-mini"
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0
    private let maxImageSize: CGFloat = 1024.0
    
    // MARK: - Error Types
    
    enum VisionError: LocalizedError {
        case noAPIKey
        case invalidImage
        case imageProcessingFailed
        case networkError(Error)
        case apiError(statusCode: Int, message: String)
        case invalidResponse
        case parsingError(String)
        case rateLimitExceeded
        case retryLimitExceeded
        
        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "OpenAI API key not found. Please configure it in Settings."
            case .invalidImage:
                return "The provided image is invalid or cannot be processed."
            case .imageProcessingFailed:
                return "Failed to process the image for API submission."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .apiError(let statusCode, let message):
                return "API error (\(statusCode)): \(message)"
            case .invalidResponse:
                return "Received an invalid response from the API."
            case .parsingError(let details):
                return "Failed to parse API response: \(details)"
            case .rateLimitExceeded:
                return "API rate limit exceeded. Please wait a moment and try again."
            case .retryLimitExceeded:
                return "Maximum retry attempts exceeded. Please try again later."
            }
        }
    }
    
    // MARK: - Response Models
    
    private struct OpenAIResponse: Codable {
        let choices: [Choice]
        
        struct Choice: Codable {
            let message: Message
        }
        
        struct Message: Codable {
            let content: String
        }
    }
    
    private struct ExtractedJSON: Codable {
        let artist: String?
        let album: String?
        let label: String?
        let catalogNumber: String?
        let year: Int?
        let rawText: String
        let confidence: Double
    }
    
    // MARK: - Singleton
    
    static let shared = VisionService()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Extract vinyl record information from an image
    /// - Parameter image: The UIImage to analyze
    /// - Returns: ExtractedData containing the parsed information
    /// - Throws: VisionError if extraction fails
    func extractVinylInfo(from image: UIImage) async throws -> ExtractedData {
        // Validate API key
        guard let apiKey = KeychainService.shared.openAIAPIKey else {
            throw VisionError.noAPIKey
        }
        
        // Resize and process image
        guard let processedImage = resizeImage(image, maxSize: maxImageSize) else {
            throw VisionError.imageProcessingFailed
        }
        
        guard let base64Image = convertToBase64(processedImage) else {
            throw VisionError.imageProcessingFailed
        }
        
        // Attempt extraction with retry logic
        return try await performExtractionWithRetry(
            base64Image: base64Image,
            apiKey: apiKey
        )
    }
    
    // MARK: - Private Methods
    
    /// Perform extraction with exponential backoff retry logic
    private func performExtractionWithRetry(
        base64Image: String,
        apiKey: String
    ) async throws -> ExtractedData {
        for attempt in 0..<maxRetries {
            do {
                return try await performExtraction(
                    base64Image: base64Image,
                    apiKey: apiKey
                )
            } catch VisionError.rateLimitExceeded {
                // For rate limits, use exponential backoff
                if attempt < maxRetries - 1 {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            } catch {
                // For other errors, store and rethrow immediately
                throw error
            }
        }
        
        // If we exhausted retries
        throw VisionError.retryLimitExceeded
    }
    
    /// Perform a single extraction attempt
    private func performExtraction(
        base64Image: String,
        apiKey: String
    ) async throws -> ExtractedData {
        // Create request
        let request = try createAPIRequest(
            base64Image: base64Image,
            apiKey: apiKey
        )
        
        // Execute request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Validate response
        try validateHTTPResponse(response)
        
        // Parse response
        return try parseResponse(data)
    }
    
    /// Create the OpenAI API request
    private func createAPIRequest(
        base64Image: String,
        apiKey: String
    ) throws -> URLRequest {
        guard let url = URL(string: apiEndpoint) else {
            throw VisionError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = buildVinylExtractionPrompt()
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 1000,
            "temperature": 0.2
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        return request
    }
    
    /// Build the specialized prompt for vinyl record extraction
    private func buildVinylExtractionPrompt() -> String {
        return """
        You are an expert at reading vinyl record labels and album covers. Analyze this image and extract the following information:
        
        - Artist name
        - Album title
        - Record label name
        - Catalog number (usually a combination of letters and numbers like "ABC-12345")
        - Release year
        
        Look carefully at all text visible in the image, including:
        - Album cover titles and credits
        - Record label text (usually in the center)
        - Small print around the edges of labels
        - Spine text if visible
        - Back cover information
        
        Return ONLY a JSON object with this exact structure (no markdown, no code blocks):
        {
            "artist": "artist name or null if not found",
            "album": "album title or null if not found",
            "label": "label name or null if not found",
            "catalogNumber": "catalog number or null if not found",
            "year": year as integer or null if not found,
            "rawText": "all text you can see in the image",
            "confidence": confidence score between 0.0 and 1.0
        }
        
        For confidence:
        - 1.0 = All fields clearly visible and certain
        - 0.8-0.9 = Most fields visible with high certainty
        - 0.6-0.7 = Some fields visible or partially obscured
        - 0.4-0.5 = Few fields visible or poor image quality
        - 0.0-0.3 = Very little readable text
        
        Be precise and only extract information you can actually see. Use null for missing fields.
        """
    }
    
    /// Validate HTTP response status code
    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisionError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return
            
        case 401:
            throw VisionError.apiError(
                statusCode: 401,
                message: "Invalid API key"
            )
            
        case 429:
            throw VisionError.rateLimitExceeded
            
        case 500...599:
            throw VisionError.apiError(
                statusCode: httpResponse.statusCode,
                message: "OpenAI server error"
            )
            
        default:
            throw VisionError.apiError(
                statusCode: httpResponse.statusCode,
                message: "Unexpected response status"
            )
        }
    }
    
    /// Parse the API response into ExtractedData
    private func parseResponse(_ data: Data) throws -> ExtractedData {
        // Decode OpenAI response
        let decoder = JSONDecoder()
        let openAIResponse: OpenAIResponse
        
        do {
            openAIResponse = try decoder.decode(OpenAIResponse.self, from: data)
        } catch {
            throw VisionError.parsingError("Failed to decode OpenAI response: \(error.localizedDescription)")
        }
        
        // Extract content string
        guard let content = openAIResponse.choices.first?.message.content else {
            throw VisionError.parsingError("No content in response")
        }
        
        // Clean content (remove markdown code blocks if present)
        let cleanedContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse extracted JSON
        guard let contentData = cleanedContent.data(using: .utf8) else {
            throw VisionError.parsingError("Failed to convert content to data")
        }
        
        let extractedJSON: ExtractedJSON
        do {
            extractedJSON = try decoder.decode(ExtractedJSON.self, from: contentData)
        } catch {
            throw VisionError.parsingError("Failed to parse extracted data: \(error.localizedDescription)")
        }
        
        // Convert to ExtractedData
        return ExtractedData(
            artist: extractedJSON.artist,
            album: extractedJSON.album,
            label: extractedJSON.label,
            catalogNumber: extractedJSON.catalogNumber,
            year: extractedJSON.year,
            rawText: extractedJSON.rawText,
            confidence: extractedJSON.confidence
        )
    }
    
    /// Resize image to reduce API token cost
    private func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage? {
        let size = image.size
        
        // Check if resizing is needed
        if size.width <= maxSize && size.height <= maxSize {
            return image
        }
        
        // Calculate new size maintaining aspect ratio
        let ratio = min(maxSize / size.width, maxSize / size.height)
        let newSize = CGSize(
            width: size.width * ratio,
            height: size.height * ratio
        )
        
        // Resize image
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    /// Convert UIImage to base64 string
    private func convertToBase64(_ image: UIImage) -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        return imageData.base64EncodedString()
    }
}

// MARK: - Convenience Extension

extension VisionService {
    
    /// Extract vinyl info from an image file path
    /// - Parameter imagePath: Path to the image file
    /// - Returns: ExtractedData containing the parsed information
    /// - Throws: VisionError if extraction fails
    func extractVinylInfo(fromPath imagePath: String) async throws -> ExtractedData {
        guard let image = UIImage(contentsOfFile: imagePath) else {
            throw VisionError.invalidImage
        }
        return try await extractVinylInfo(from: image)
    }
}
