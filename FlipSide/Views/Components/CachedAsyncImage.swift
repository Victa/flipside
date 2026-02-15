//
//  CachedAsyncImage.swift
//  FlipSide
//
//  Cached AsyncImage for offline support
//

import SwiftUI

/// AsyncImage wrapper with persistent caching for offline support
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var cachedImage: UIImage?
    
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
            if let cachedImage = cachedImage {
                content(Image(uiImage: cachedImage))
            } else if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        content(image)
                            .onAppear {
                                // Cache the downloaded image
                                cacheImage(from: url)
                            }
                    case .empty, .failure:
                        placeholder()
                    @unknown default:
                        placeholder()
                    }
                }
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadCachedImage()
        }
    }
    
    private func loadCachedImage() {
        guard let url = url else { return }
        
        // Check URLCache first
        let request = URLRequest(url: url)
        if let cachedResponse = URLCache.shared.cachedResponse(for: request),
           let image = UIImage(data: cachedResponse.data) {
            self.cachedImage = image
        }
    }
    
    private func cacheImage(from url: URL) {
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    // Store in URLCache
                    let cachedResponse = CachedURLResponse(response: response, data: data)
                    URLCache.shared.storeCachedResponse(cachedResponse, for: URLRequest(url: url))
                    
                    await MainActor.run {
                        self.cachedImage = image
                    }
                }
            } catch {
                print("Failed to cache image: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Convenience initializer for simple cases

extension CachedAsyncImage where Content == Image, Placeholder == Color {
    init(url: URL?) {
        self.init(
            url: url,
            content: { image in image },
            placeholder: { Color.gray.opacity(0.2) }
        )
    }
}
