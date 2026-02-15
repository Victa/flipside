import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var libraryViewModel = DiscogsLibraryViewModel.shared
    @StateObject private var authService = DiscogsAuthService.shared

    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = "Error"
    @State private var isRefreshingLibrary = false
    @State private var refreshStatusMessage: String?
    @State private var refreshStatusStyle: Color = .secondary
    @State private var showingDisconnectConfirmation = false

    private let keychainService = KeychainService.shared
    private let cacheService = SwiftDataLibraryCache.shared

    let onCredentialsChanged: () -> Void

    init(onCredentialsChanged: @escaping () -> Void = {}) {
        self.onCredentialsChanged = onCredentialsChanged
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(action: refreshLibrary) {
                        HStack {
                            Spacer()
                            if isRefreshingLibrary {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .padding(.trailing, 8)
                            }
                            Text("Refresh Collection/Wantlist")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isRefreshingLibrary || !authService.isConnected)

                    if let refreshStatusMessage {
                        Text(refreshStatusMessage)
                            .font(.caption)
                            .foregroundStyle(refreshStatusStyle)
                    }

                    refreshTimestampRow
                } header: {
                    Text("Refresh Data")
                } footer: {
                    Text("Syncs your Discogs collection and wantlist into the local cache.")
                        .font(.caption)
                }

                Section {
                    Button(role: .destructive) {
                        showingDisconnectConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Disconnect Discogs + Remove OpenAI Key")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                } footer: {
                    Text("This also clears cached collection and wantlist data from this device.")
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .confirmationDialog(
                "Disconnect Discogs and remove your OpenAI key?",
                isPresented: $showingDisconnectConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disconnect and Clear Data", role: .destructive) {
                    disconnectAndClearAllData()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove Discogs credentials, remove your OpenAI key, and clear cached collection/wantlist data.")
            }
            .onAppear {
                authService.refreshPublishedState()
                libraryViewModel.prepareState(listType: .collection, modelContext: modelContext)
                libraryViewModel.prepareState(listType: .wantlist, modelContext: modelContext)
            }
        }
    }

    private var refreshTimestampRow: some View {
        HStack {
            Text("Last Refresh:")
                .foregroundStyle(.secondary)
            Spacer()
            let latest = [
                libraryViewModel.collectionState.lastRefreshDate,
                libraryViewModel.wantlistState.lastRefreshDate
            ]
                .compactMap { $0 }
                .max()

            if let latest {
                Text(latest.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            } else {
                Text("Never")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private func refreshLibrary() {
        isRefreshingLibrary = true
        refreshStatusMessage = "Refresh in progress..."
        refreshStatusStyle = .secondary

        Task {
            let result = await libraryViewModel.refreshAllIncremental(
                modelContext: modelContext,
                onInitialGateReady: {}
            )

            await MainActor.run {
                isRefreshingLibrary = false
                if let failure = result.failureMessage {
                    refreshStatusMessage = "Refresh failed: \(failure)"
                    refreshStatusStyle = .red
                } else {
                    refreshStatusMessage = result.successMessage
                    refreshStatusStyle = .green
                }
            }
        }
    }

    private func disconnectAndClearAllData() {
        do {
            try authService.disconnect()
            try keychainService.delete(.openAIAPIKey)
            try cacheService.clearLibraryData(in: modelContext)

            libraryViewModel.resetLibraryState()
            refreshStatusMessage = nil
            authService.refreshPublishedState()
            onCredentialsChanged()
            dismiss()
        } catch {
            alertTitle = "Error"
            alertMessage = "Failed to reset credentials and cached data: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

#Preview {
    SettingsView()
}
