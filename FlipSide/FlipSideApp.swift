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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Scan.self)
    }
}
