//
//  ProcessingView.swift
//  FlipSide
//
//  Processing view shown during Vision API call
//

import SwiftUI

struct ProcessingView: View {
    let image: UIImage
    
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
            
            Text("Reading text from image")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Processing")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ProcessingView(image: UIImage(systemName: "photo")!)
    }
}
