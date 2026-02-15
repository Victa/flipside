import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var libraryViewModel = DiscogsLibraryViewModel.shared

    @State private var openAIAPIKey: String = ""
    @State private var discogsPersonalToken: String = ""
    @State private var discogsUsername: String = ""
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""
    @State private var saveAlertTitle = "Success"
    @State private var isSavingOpenAI = false
    @State private var isSavingDiscogs = false
    @State private var isSavingUsername = false
    @State private var isRefreshingLibrary = false
    @State private var refreshStatusMessage: String?
    @State private var refreshStatusStyle: Color = .secondary
    private let keychainService = KeychainService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Enter your Discogs username", text: $discogsUsername)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    HStack {
                        Text("Current Status:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !(keychainService.discogsUsername ?? "").isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Saved")
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Not set")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)

                    Button(action: saveDiscogsUsername) {
                        HStack {
                            Spacer()
                            if isSavingUsername {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .padding(.trailing, 8)
                            }
                            Text("Save Discogs Username")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(discogsUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingUsername)
                } header: {
                    Text("Discogs Username")
                } footer: {
                    Text("Required for syncing your collection and wantlist.")
                        .font(.caption)
                }

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
                    .disabled(isRefreshingLibrary || (keychainService.discogsUsername ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let refreshStatusMessage {
                        Text(refreshStatusMessage)
                            .font(.caption)
                            .foregroundStyle(refreshStatusStyle)
                    }

                    refreshTimestampRow
                } header: {
                    Text("Library Sync")
                } footer: {
                    Text("Uses your Discogs username to fetch collection and wantlist, then updates local cache.")
                        .font(.caption)
                }

                Section {
                    SecureField("Enter your OpenAI API key", text: $openAIAPIKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
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
                    SecureField("Enter your Discogs token", text: $discogsPersonalToken)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    HStack {
                        Text("Current Status:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if keychainService.discogsPersonalToken != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Saved")
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Not set")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)

                    Button(action: saveDiscogsToken) {
                        HStack {
                            Spacer()
                            if isSavingDiscogs {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .padding(.trailing, 8)
                            }
                            Text("Save Discogs Token")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(discogsPersonalToken.isEmpty || isSavingDiscogs)
                } header: {
                    Text("Discogs Personal Access Token")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Optional but recommended for better API rate limits (60 requests/min vs 25 requests/min).")
                        Link("Generate a personal access token", destination: URL(string: "https://www.discogs.com/settings/developers")!)
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
                        keychainService.discogsPersonalToken == nil &&
                        keychainService.discogsUsername == nil
                    )
                } footer: {
                    Text("This will remove API keys and Discogs username from secure storage.")
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

    private func loadCurrentValues() {
        openAIAPIKey = ""
        discogsPersonalToken = ""
        discogsUsername = keychainService.discogsUsername ?? ""
    }

    private func saveDiscogsUsername() {
        isSavingUsername = true

        Task {
            do {
                try keychainService.setDiscogsUsername(discogsUsername.trimmingCharacters(in: .whitespacesAndNewlines))
                await MainActor.run {
                    isSavingUsername = false
                    saveAlertTitle = "Success"
                    saveAlertMessage = "Discogs username has been saved securely."
                    showingSaveAlert = true
                }
            } catch {
                await MainActor.run {
                    isSavingUsername = false
                    saveAlertTitle = "Error"
                    saveAlertMessage = "Failed to save Discogs username: \(error.localizedDescription)"
                    showingSaveAlert = true
                }
            }
        }
        if let username = keychainService.discogsUsername {
            discogsUsername = username // Show username (not sensitive)
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

    private func saveDiscogsToken() {
        isSavingDiscogs = true

        Task {
            do {
                try keychainService.setDiscogsPersonalToken(discogsPersonalToken)

                await MainActor.run {
                    isSavingDiscogs = false
                    saveAlertTitle = "Success"
                    saveAlertMessage = "Discogs token has been saved securely."
                    showingSaveAlert = true
                    discogsPersonalToken = ""
                }
            } catch {
                await MainActor.run {
                    isSavingDiscogs = false
                    saveAlertTitle = "Error"
                    saveAlertMessage = "Failed to save Discogs token: \(error.localizedDescription)"
                    showingSaveAlert = true
                }
            }
        }
    }
    private func clearAllKeys() {
        do {
            try keychainService.deleteAll()

            openAIAPIKey = ""
            discogsPersonalToken = ""
            discogsUsername = ""
            refreshStatusMessage = nil
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
