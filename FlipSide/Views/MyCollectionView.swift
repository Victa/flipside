import SwiftUI

struct MyCollectionView: View {
    @ObservedObject var viewModel: DiscogsLibraryViewModel
    let onSelect: (LibraryEntry) -> Void

    var body: some View {
        LibraryListView(
            listType: .collection,
            viewModel: viewModel,
            onSelect: onSelect
        )
    }
}

#Preview {
    MyCollectionView(viewModel: DiscogsLibraryViewModel.shared, onSelect: { _ in })
}
