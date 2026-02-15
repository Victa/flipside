import SwiftUI
import UIKit

/// Async image wrapper with in-memory + URLCache support and request coalescing.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var cachedImage: UIImage?
    @State private var loadTask: Task<Void, Never>?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let cachedImage {
                content(Image(uiImage: cachedImage))
            } else {
                placeholder()
            }
        }
        .onAppear {
            startLoading()
        }
        .onChange(of: url) { _, _ in
            startLoading()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func startLoading() {
        loadTask?.cancel()
        cachedImage = nil

        guard let url else { return }

        loadTask = Task {
            if let immediate = await CachedImageLoader.shared.cachedImage(for: url) {
                await MainActor.run {
                    cachedImage = immediate
                }
                return
            }

            let loaded = await CachedImageLoader.shared.loadImage(for: url)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                cachedImage = loaded
            }
        }
    }
}

actor CachedImageLoader {
    static let shared = CachedImageLoader()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    func cachedImage(for url: URL) -> UIImage? {
        if let memoryImage = memoryCache.object(forKey: url as NSURL) {
            return memoryImage
        }

        let request = URLRequest(url: url)
        if let cachedResponse = URLCache.shared.cachedResponse(for: request),
           let image = UIImage(data: cachedResponse.data) {
            memoryCache.setObject(image, forKey: url as NSURL)
            return image
        }

        return nil
    }

    func loadImage(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) {
            return cached
        }

        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            let request = URLRequest(url: url)
            do {
                PerformanceMetrics.incrementCounter("image_network_requests")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let image = UIImage(data: data) else {
                    return nil
                }

                memoryCache.setObject(image, forKey: url as NSURL)
                URLCache.shared.storeCachedResponse(
                    CachedURLResponse(response: response, data: data),
                    for: request
                )
                return image
            } catch {
                return nil
            }
        }

        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }
}

extension CachedAsyncImage where Content == Image, Placeholder == Color {
    init(url: URL?) {
        self.init(
            url: url,
            content: { image in image },
            placeholder: { Color.gray.opacity(0.2) }
        )
    }
}
