//
//  PhotoLibraryPicker.swift
//  FlipSide
//
//  Created on 2/14/26.
//

import SwiftUI
import PhotosUI

/// Helper view for photo library selection using PhotosPicker
struct PhotoLibraryPicker<Label: View>: View {
    @Binding var selectedImage: UIImage?
    @State private var selectedItem: PhotosPickerItem?
    
    let onImageSelected: (UIImage) -> Void
    let label: () -> Label
    
    init(
        selectedImage: Binding<UIImage?>,
        @ViewBuilder label: @escaping () -> Label,
        onImageSelected: @escaping (UIImage) -> Void
    ) {
        self._selectedImage = selectedImage
        self.label = label
        self.onImageSelected = onImageSelected
    }
    
    var body: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            label()
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

// Convenience initializer for default label
extension PhotoLibraryPicker where Label == SwiftUI.Label<Text, Image> {
    init(
        selectedImage: Binding<UIImage?>,
        onImageSelected: @escaping (UIImage) -> Void
    ) {
        self._selectedImage = selectedImage
        self.onImageSelected = onImageSelected
        self.label = {
            Label("Choose from Library", systemImage: "photo.on.rectangle")
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
