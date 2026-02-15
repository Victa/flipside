import SwiftUI
import SwiftData

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext

    @StateObject private var authService = DiscogsAuthService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var libraryViewModel = DiscogsLibraryViewModel.shared

    @State private var step: OnboardingStep = .discogs
    @State private var openAIAPIKey = ""
    @State private var isConnectingDiscogs = false
    @State private var discogsErrorMessage: String?
    @State private var isSavingOpenAI = false
    @State private var openAIErrorMessage: String?
    @State private var isSyncing = false
    @State private var syncErrorMessage: String?
    @State private var hasAttemptedInitialSync = false

    private let keychainService = KeychainService.shared

    let onCompleted: () -> Void
    let onCredentialsChanged: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                progressHeader

                stepContent

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .navigationTitle("Welcome to Flip Side")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                authService.refreshPublishedState()
                step = initialStep()
                if step == .syncing {
                    await refreshLibraryAfterOnboarding()
                }
            }
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 8) {
            Text(step.title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(step.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Step \(step.order) of 3")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .discogs:
            discogsStepView
        case .openAI:
            openAIStepView
        case .syncing:
            syncingStepView
        }
    }

    private var discogsStepView: some View {
        VStack(spacing: 16) {
            if let discogsErrorMessage {
                Text(discogsErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if !networkMonitor.isConnected {
                Text("You're offline. Connect to the internet to authorize Discogs.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button(action: connectDiscogs) {
                HStack {
                    Spacer()
                    if isConnectingDiscogs {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .padding(.trailing, 8)
                    }
                    Text("Connect Discogs")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConnectingDiscogs || !networkMonitor.isConnected)
        }
    }

    private var openAIStepView: some View {
        VStack(spacing: 16) {
            SecureField("Paste your OpenAI API key", text: $openAIAPIKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if let openAIErrorMessage {
                Text(openAIErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Link("Get your API key from OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                .font(.caption)

            Button(action: saveOpenAIKeyAndContinue) {
                HStack {
                    Spacer()
                    if isSavingOpenAI {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .padding(.trailing, 8)
                    }
                    Text("Validate & Continue")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSavingOpenAI || openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var syncingStepView: some View {
        VStack(spacing: 16) {
            if isSyncing {
                ProgressView("Refreshing your Discogs collection and wantlist...")
                    .multilineTextAlignment(.center)
            }

            if let syncErrorMessage {
                Text(syncErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    Task {
                        await refreshLibraryAfterOnboarding(forceRetry: true)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Continue") {
                    onCompleted()
                }
                .buttonStyle(.bordered)
            }

            if !isSyncing && syncErrorMessage == nil && hasAttemptedInitialSync {
                Text("Library sync complete.")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private func initialStep() -> OnboardingStep {
        let token = keychainService.discogsOAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secret = keychainService.discogsOAuthTokenSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = keychainService.discogsUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasDiscogs = !token.isEmpty && !secret.isEmpty && !username.isEmpty
        let hasOpenAI = hasStoredOpenAIKey

        if !hasDiscogs {
            return .discogs
        }

        if !hasOpenAI {
            return .openAI
        }

        return .syncing
    }

    private var hasStoredOpenAIKey: Bool {
        guard let value = keychainService.openAIAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !value.isEmpty
    }

    private func connectDiscogs() {
        guard networkMonitor.isConnected else {
            discogsErrorMessage = "You're offline. Connect to the internet and try again."
            return
        }

        isConnectingDiscogs = true
        discogsErrorMessage = nil

        Task {
            do {
                try await authService.connect()

                await MainActor.run {
                    isConnectingDiscogs = false
                    onCredentialsChanged()

                    if hasStoredOpenAIKey {
                        step = .syncing
                        Task {
                            await refreshLibraryAfterOnboarding()
                        }
                    } else {
                        step = .openAI
                    }
                }
            } catch {
                await MainActor.run {
                    isConnectingDiscogs = false
                    discogsErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveOpenAIKeyAndContinue() {
        let trimmed = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            openAIErrorMessage = "Enter a valid OpenAI API key."
            return
        }

        isSavingOpenAI = true
        openAIErrorMessage = nil

        Task {
            do {
                try keychainService.setOpenAIAPIKey(trimmed)

                await MainActor.run {
                    isSavingOpenAI = false
                    openAIAPIKey = ""
                    onCredentialsChanged()
                    step = .syncing
                    Task {
                        await refreshLibraryAfterOnboarding()
                    }
                }
            } catch {
                await MainActor.run {
                    isSavingOpenAI = false
                    openAIErrorMessage = "Failed to save key: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func refreshLibraryAfterOnboarding(forceRetry: Bool = false) async {
        if isSyncing {
            return
        }

        if hasAttemptedInitialSync && !forceRetry {
            return
        }

        guard networkMonitor.isConnected else {
            syncErrorMessage = "You're offline. Connect to the internet to refresh your library."
            hasAttemptedInitialSync = true
            return
        }

        hasAttemptedInitialSync = true
        isSyncing = true
        syncErrorMessage = nil

        let result = await libraryViewModel.refreshAll(modelContext: modelContext)

        isSyncing = false

        if let failure = result.failureMessage {
            syncErrorMessage = "Refresh failed: \(failure)"
        } else {
            syncErrorMessage = nil
            onCompleted()
        }
    }
}

enum OnboardingStep {
    case discogs
    case openAI
    case syncing

    var order: Int {
        switch self {
        case .discogs:
            return 1
        case .openAI:
            return 2
        case .syncing:
            return 3
        }
    }

    var title: String {
        switch self {
        case .discogs:
            return "Connect Discogs"
        case .openAI:
            return "Add OpenAI Key"
        case .syncing:
            return "Sync Your Library"
        }
    }

    var subtitle: String {
        switch self {
        case .discogs:
            return "Connect your Discogs account to load your collection and wantlist."
        case .openAI:
            return "Paste your OpenAI API key to enable vinyl text extraction."
        case .syncing:
            return "We'll do an initial refresh so your data is ready."
        }
    }
}
