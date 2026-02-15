//
//  ProcessingView.swift
//  FlipSide
//
//  Processing view shown during Vision API call
//

import SwiftUI

enum ProcessingStep {
    case readingImage
    case searchingDiscogs
}

struct ProcessingView: View {
    let image: UIImage
    let currentStep: ProcessingStep
    
    var body: some View {
        VStack(spacing: 20) {
            // Show the captured image
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 4)
                .padding()
            
            // Loading indicator
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            
            Text("Analyzing vinyl record...")
                .font(.headline)
            
            VStack(spacing: 8) {
                ProcessingStepRow(
                    title: "Reading text from image",
                    step: .readingImage,
                    currentStep: currentStep
                )
                
                ProcessingStepRow(
                    title: "Searching Discogs database",
                    step: .searchingDiscogs,
                    currentStep: currentStep
                )
            }
        }
        .padding()
        .navigationTitle("Processing")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProcessingStepRow: View {
    let title: String
    let step: ProcessingStep
    let currentStep: ProcessingStep
    
    private var isCurrentStep: Bool {
        step == currentStep
    }
    
    private var isCompleted: Bool {
        switch (step, currentStep) {
        case (.readingImage, .searchingDiscogs):
            return true
        default:
            return false
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Group {
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if isCurrentStep {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            
            // Step title
            Text(title)
                .font(.subheadline)
                .foregroundStyle(isCurrentStep ? .primary : .secondary)
                .fontWeight(isCurrentStep ? .medium : .regular)
            
            Spacer()
        }
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        ProcessingView(image: UIImage(systemName: "photo")!, currentStep: .readingImage)
    }
}
