//
//  PhotoLibraryPicker.swift
//  FlipSide
//
//  Created on 2/14/26.
//

import SwiftUI
import PhotosUI

/// Helper view for photo library selection using PhotosPicker
struct PhotoLibraryPicker: View {
    @Binding var selectedImage: UIImage?
    @State private var selectedItem: PhotosPickerItem?
    
    let onImageSelected: (UIImage) -> Void
    
    var body: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Label("Choose from Library", systemImage: "photo.on.rectangle")
        }
        .onChange(of: selectedItem) { oldValue, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImage = image
                        onImageSelected(image)
                    }
                }
            }
        }
    }
}

/// Extension to handle PhotosPicker item loading
extension PhotosPickerItem {
    func loadImage() async throws -> UIImage? {
        guard let data = try await self.loadTransferable(type: Data.self) else {
            return nil
        }
        return UIImage(data: data)
    }
}
