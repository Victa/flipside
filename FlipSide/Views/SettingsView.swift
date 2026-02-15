import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var libraryViewModel = DiscogsLibraryViewModel.shared
    @StateObject private var authService = DiscogsAuthService.shared

    @State private var openAIAPIKey: String = ""
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""
    @State private var saveAlertTitle = "Success"
    @State private var isSavingOpenAI = false
    @State private var isRefreshingLibrary = false
    @State private var refreshStatusMessage: String?
    @State private var refreshStatusStyle: Color = .secondary
    private let keychainService = KeychainService.shared

    var body: some View {
        NavigationStack {
            Form {
                discogsConnectionSection

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
                    Text("Library Sync")
                } footer: {
                    Text("Syncs your Discogs collection and wantlist into the local cache.")
                        .font(.caption)
                }

                Section {
                    SecureField("Enter your OpenAI API key", text: $openAIAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()

                    HStack {
                        Text("Current Status:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if keychainService.openAIAPIKey != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Saved")
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text("Not set")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)

                    Button(action: saveOpenAIKey) {
                        HStack {
                            Spacer()
                            if isSavingOpenAI {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .padding(.trailing, 8)
                            }
                            Text("Save OpenAI Key")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(openAIAPIKey.isEmpty || isSavingOpenAI)
                } header: {
                    Text("OpenAI API Key")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Required for vinyl record text extraction using GPT-4o-mini Vision.")
                        Link("Get your API key from OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                    }
                }

                Section {
                    Button(role: .destructive, action: clearAllKeys) {
                        HStack {
                            Spacer()
                            Text("Clear All Keys")
                            Spacer()
                        }
                    }
                    .disabled(
                        keychainService.openAIAPIKey == nil &&
                        keychainService.discogsOAuthToken == nil &&
                        keychainService.discogsOAuthTokenSecret == nil &&
                        keychainService.discogsUsername == nil
                    )
                } footer: {
                    Text("This removes OpenAI and Discogs OAuth credentials from secure storage.")
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
            .alert(saveAlertTitle, isPresented: $showingSaveAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveAlertMessage)
            }
            .onAppear {
                loadCurrentValues()
                authService.refreshPublishedState()
            }
        }
    }

    private var discogsConnectionSection: some View {
        Section {
            HStack {
                Text("Current Status:")
                    .foregroundStyle(.secondary)
                Spacer()
                if authService.isConnected, let username = authService.currentUsername {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Connected as \(username)")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Not connected")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if authService.isConnected {
                Button(role: .destructive, action: disconnectDiscogs) {
                    HStack {
                        Spacer()
                        Text("Disconnect Discogs")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            } else {
                Button(action: connectDiscogs) {
                    HStack {
                        Spacer()
                        if authService.isConnecting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .padding(.trailing, 8)
                        }
                        Text("Connect Discogs")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(authService.isConnecting)
            }
        } header: {
            Text("Discogs Account")
        } footer: {
            Text("Connect once with OAuth to search releases and manage collection/wantlist.")
                .font(.caption)
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

    private func loadCurrentValues() {
        openAIAPIKey = ""
    }

    private func connectDiscogs() {
        Task {
            do {
                try await authService.connect()
                await MainActor.run {
                    saveAlertTitle = "Connected"
                    saveAlertMessage = "Discogs account connected successfully."
                    showingSaveAlert = true
                }
            } catch {
                await MainActor.run {
                    saveAlertTitle = "Error"
                    saveAlertMessage = "Failed to connect Discogs account: \(error.localizedDescription)"
                    showingSaveAlert = true
                }
            }
        }
    }

    private func disconnectDiscogs() {
        do {
            try authService.disconnect()
            saveAlertTitle = "Disconnected"
            saveAlertMessage = "Discogs account has been disconnected."
            showingSaveAlert = true
            refreshStatusMessage = nil
        } catch {
            saveAlertTitle = "Error"
            saveAlertMessage = "Failed to disconnect Discogs account: \(error.localizedDescription)"
            showingSaveAlert = true
        }
    }

    private func refreshLibrary() {
        isRefreshingLibrary = true
        refreshStatusMessage = "Refresh in progress..."
        refreshStatusStyle = .secondary

        Task {
            let result = await libraryViewModel.refreshAll(modelContext: modelContext)

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

    private func saveOpenAIKey() {
        isSavingOpenAI = true

        Task {
            do {
                try keychainService.setOpenAIAPIKey(openAIAPIKey)

                await MainActor.run {
                    isSavingOpenAI = false
                    saveAlertTitle = "Success"
                    saveAlertMessage = "OpenAI API key has been saved securely."
                    showingSaveAlert = true
                    openAIAPIKey = ""
                }
            } catch {
                await MainActor.run {
                    isSavingOpenAI = false
                    saveAlertTitle = "Error"
                    saveAlertMessage = "Failed to save OpenAI key: \(error.localizedDescription)"
                    showingSaveAlert = true
                }
            }
        }
    }

    private func clearAllKeys() {
        do {
            try keychainService.deleteAll()

            openAIAPIKey = ""
            refreshStatusMessage = nil
            authService.refreshPublishedState()
            saveAlertTitle = "Cleared"
            saveAlertMessage = "All saved credentials have been removed from secure storage."
            showingSaveAlert = true
        } catch {
            saveAlertTitle = "Error"
            saveAlertMessage = "Failed to clear credentials: \(error.localizedDescription)"
            showingSaveAlert = true
        }
    }
}

#Preview {
    SettingsView()
}
