import SwiftUI
import SwiftData

@main
struct FlipSideApp: App {
    init() {
        let cache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            directory: nil
        )
        URLCache.shared = cache
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Scan.self, LibraryEntry.self, LibrarySyncState.self])
    }
}
