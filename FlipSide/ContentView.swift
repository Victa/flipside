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
    var body: some View {
        NavigationStack {
            VStack {
                Text("History View")
                    .font(.largeTitle)
                Text("Past scans will appear here...")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Flip Side")
        }
    }
}

#Preview {
    ContentView()
}
