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
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Main content area
                VStack {
                    Text("History View")
                        .font(.largeTitle)
                    Text("Past scans will appear here...")
                        .foregroundStyle(.secondary)
                }
                .navigationTitle("Flip Side")
                
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
            .sheet(isPresented: $showingImageCapture) {
                // ImageCaptureSheet will be implemented in step 6
                Text("Image Capture Options")
                    .presentationDetents([.medium])
            }
        }
    }
}

#Preview {
    ContentView()
}
