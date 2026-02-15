import SwiftUI

struct MyWantlistView: View {
    @ObservedObject var viewModel: DiscogsLibraryViewModel
    let onSelect: (LibraryEntry) -> Void

    var body: some View {
        LibraryListView(
            listType: .wantlist,
            viewModel: viewModel,
            onSelect: onSelect
        )
    }
}

#Preview {
    MyWantlistView(viewModel: DiscogsLibraryViewModel.shared, onSelect: { _ in })
}
