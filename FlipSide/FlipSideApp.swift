//
//  FlipSideApp.swift
//  FlipSide
//
//  Created on 2/14/26.
//

import SwiftUI
import SwiftData

@main
struct FlipSideApp: App {
    init() {
        // Configure URLCache for offline image support
        // 50MB memory cache, 200MB disk cache
        let cache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,  // 50 MB
            diskCapacity: 200 * 1024 * 1024,   // 200 MB
            directory: nil
        )
        URLCache.shared = cache
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Scan.self)
    }
}
