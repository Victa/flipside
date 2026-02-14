//
//  ResultView.swift
//  FlipSide
//
//  Displays extracted vinyl record information
//

import SwiftUI

struct ResultView: View {
    let image: UIImage
    let extractedData: ExtractedData
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Captured image
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
                    .padding(.horizontal)
                
                // Confidence indicator
                confidenceSection
                
                // Extracted fields
                extractedFieldsSection
                
                // Raw text section
                rawTextSection
            }
            .padding(.vertical)
        }
        .navigationTitle("Extraction Results")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Confidence Section
    
    private var confidenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Confidence")
                    .font(.headline)
                Spacer()
                Text(confidenceText)
                    .font(.subheadline)
                    .foregroundStyle(confidenceColor)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(confidenceColor)
                        .frame(
                            width: geometry.size.width * extractedData.confidence,
                            height: 8
                        )
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal)
    }
    
    private var confidenceText: String {
        let percentage = Int(extractedData.confidence * 100)
        return "\(percentage)%"
    }
    
    private var confidenceColor: Color {
        switch extractedData.confidence {
        case 0.8...1.0:
            return .green
        case 0.6..<0.8:
            return .orange
        default:
            return .red
        }
    }
    
    // MARK: - Extracted Fields Section
    
    private var extractedFieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Extracted Information")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 0) {
                if let artist = extractedData.artist {
                    ExtractedFieldRow(label: "Artist", value: artist)
                    Divider()
                }
                
                if let album = extractedData.album {
                    ExtractedFieldRow(label: "Album", value: album)
                    Divider()
                }
                
                if let label = extractedData.label {
                    ExtractedFieldRow(label: "Label", value: label)
                    Divider()
                }
                
                if let catalogNumber = extractedData.catalogNumber {
                    ExtractedFieldRow(label: "Catalog #", value: catalogNumber)
                    Divider()
                }
                
                if let year = extractedData.year {
                    ExtractedFieldRow(label: "Year", value: String(year))
                }
                
                // Show message if no fields were extracted
                if extractedData.artist == nil &&
                   extractedData.album == nil &&
                   extractedData.label == nil &&
                   extractedData.catalogNumber == nil &&
                   extractedData.year == nil {
                    Text("No structured information extracted")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }
    
    // MARK: - Raw Text Section
    
    private var rawTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw Text")
                .font(.headline)
                .padding(.horizontal)
            
            Text(extractedData.rawText)
                .font(.body)
                .foregroundStyle(.primary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
        }
    }
}

// MARK: - Supporting Views

struct ExtractedFieldRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ResultView(
            image: UIImage(systemName: "photo")!,
            extractedData: ExtractedData(
                artist: "Miles Davis",
                album: "Kind of Blue",
                label: "Columbia",
                catalogNumber: "CL 1355",
                year: 1959,
                rawText: "Miles Davis - Kind of Blue, Columbia Records CL 1355, Released 1959",
                confidence: 0.92
            )
        )
    }
}
