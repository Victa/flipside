import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        AppRootTabView()
    }
}

struct AppRootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var collectionEntries: [LibraryEntry]
    @Query private var wantlistEntries: [LibraryEntry]

    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var libraryViewModel = DiscogsLibraryViewModel.shared

    @State private var selectedTab: RootTab = .collection
    @State private var showingImageCapture = false
    @State private var showingSettings = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isAPIKeyConfigured = false
    @State private var navigationPath = NavigationPath()
    @State private var isProcessing = false
    @State private var currentProcessingStep: ProcessingStep = .readingImage

    private let keychainService = KeychainService.shared

    init() {
        let collectionRaw = LibraryListType.collection.rawValue
        let wantlistRaw = LibraryListType.wantlist.rawValue
        _collectionEntries = Query(
            filter: #Predicate<LibraryEntry> { entry in
                entry.listTypeRaw == collectionRaw
            }
        )
        _wantlistEntries = Query(
            filter: #Predicate<LibraryEntry> { entry in
                entry.listTypeRaw == wantlistRaw
            }
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                TabView(selection: $selectedTab) {
                    MyCollectionView(viewModel: libraryViewModel) { entry in
                        navigationPath.append(
                            DetailDestination(
                                match: entry.toDiscogsMatch(),
                                scanId: nil,
                                source: .library
                            )
                        )
                    }
                    .tabItem {
                        Label("My Collection", systemImage: "square.stack.3d.up")
                    }
                    .tag(RootTab.collection)

                    MyWantlistView(viewModel: libraryViewModel) { entry in
                        navigationPath.append(
                            DetailDestination(
                                match: entry.toDiscogsMatch(),
                                scanId: nil,
                                source: .library
                            )
                        )
                    }
                    .tabItem {
                        Label("My Wantlist", systemImage: "heart")
                    }
                    .tag(RootTab.wantlist)
                }

                floatingActionButton
            }
            .navigationTitle(selectedTabTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ProcessingDestination.self) { destination in
                ProcessingView(image: destination.image, currentStep: currentProcessingStep)
                    .task {
                        await performExtraction(image: destination.image)
                    }
            }
            .navigationDestination(for: ResultDestination.self) { destination in
                ResultView(
                    image: destination.image,
                    extractedData: destination.extractedData,
                    discogsMatches: destination.discogsMatches,
                    discogsError: destination.discogsError,
                    scanId: destination.scanId,
                    onMatchSelected: { match, index in
                        if let scanId = destination.scanId {
                            let fetchDescriptor = FetchDescriptor<Scan>(
                                predicate: #Predicate { $0.id == scanId }
                            )
                            if let scan = try? modelContext.fetch(fetchDescriptor).first {
                                scan.selectedMatchIndex = index
                                try? modelContext.save()
                            }
                        }

                        navigationPath.append(
                            DetailDestination(
                                match: match,
                                scanId: destination.scanId,
                                source: destination.source
                            )
                        )
                    }
                )
            }
            .navigationDestination(for: DetailDestination.self) { destination in
                DetailView(
                    match: destination.match,
                    scanId: destination.scanId,
                    onDone: {
                        switch destination.source {
                        case .scanUtility:
                            navigationPath.removeLast(navigationPath.count)
                        case .library:
                            if navigationPath.count > 0 {
                                navigationPath.removeLast()
                            }
                        }
                    }
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "gearshape")

                            if !isAPIKeyConfigured {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingImageCapture) {
                ImageCaptureSheet { image in
                    handleImageCaptured(image)
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                updateAPIKeyStatus()
            }) {
                SettingsView()
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertMessage.contains("Error") ? "Error" : "Success"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        if alertMessage.contains("Error") {
                            navigationPath.removeLast(navigationPath.count)
                        }
                    }
                )
            }
            .onAppear {
                updateAPIKeyStatus()
                checkFirstRun()
            }
        }
    }

    private var selectedTabTitle: String {
        switch selectedTab {
        case .collection:
            return "My Collection (\(collectionEntries.count))"
        case .wantlist:
            return "My Wantlist (\(wantlistEntries.count))"
        }
    }

    private var floatingActionButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    if !networkMonitor.isConnected {
                        alertMessage = "You're currently offline. Internet connection is required to scan new records."
                        showAlert = true
                    } else {
                        showingImageCapture = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .disabled(!isAPIKeyConfigured || isProcessing)
                .opacity(isAPIKeyConfigured && !isProcessing ? 1.0 : 0.5)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private func updateAPIKeyStatus() {
        isAPIKeyConfigured = keychainService.openAIAPIKey != nil
    }

    private func checkFirstRun() {
        if keychainService.openAIAPIKey == nil {
            showingSettings = true
        }
    }

    private func handleImageCaptured(_ image: UIImage) {
        currentProcessingStep = .readingImage
        navigationPath.append(ProcessingDestination(image: image))
    }

    private func performExtraction(image: UIImage) async {
        isProcessing = true

        await MainActor.run {
            currentProcessingStep = .readingImage
        }

        do {
            var extractedData = try await VisionService.shared.extractVinylInfo(from: image)

            extractedData = ExtractedData(
                artist: extractedData.artist?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true || extractedData.artist?.lowercased() == "null" ? nil : extractedData.artist,
                album: extractedData.album?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true || extractedData.album?.lowercased() == "null" ? nil : extractedData.album,
                label: extractedData.label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true || extractedData.label?.lowercased() == "null" ? nil : extractedData.label,
                catalogNumber: extractedData.catalogNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true || extractedData.catalogNumber?.lowercased() == "null" ? nil : extractedData.catalogNumber,
                year: extractedData.year,
                tracks: extractedData.tracks,
                rawText: extractedData.rawText,
                confidence: extractedData.confidence
            )

            await MainActor.run {
                currentProcessingStep = .searchingDiscogs
            }

            var discogsMatches: [DiscogsMatch] = []
            var discogsError: String?

            if DiscogsAuthService.shared.isConnected {
                do {
                    discogsMatches = try await DiscogsService.shared.searchReleases(for: extractedData)
                } catch {
                    discogsError = error.localizedDescription
                    print("Discogs search failed: \(error.localizedDescription)")
                }
            } else {
                discogsError = "Discogs account not connected. Connect your account in Settings to search for matches."
            }

            await MainActor.run {
                navigationPath.removeLast()
                navigationPath.append(
                    ResultDestination(
                        scanId: nil,
                        image: image,
                        extractedData: extractedData,
                        discogsMatches: discogsMatches,
                        discogsError: discogsError,
                        source: .scanUtility
                    )
                )
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                alertMessage = "Error: \(error.localizedDescription)"
                showAlert = true
                isProcessing = false
            }
        }
    }
}

private enum RootTab: Hashable {
    case collection
    case wantlist
}

struct ProcessingDestination: Hashable {
    let id = UUID()
    let image: UIImage

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ProcessingDestination, rhs: ProcessingDestination) -> Bool {
        lhs.id == rhs.id
    }
}

struct ResultDestination: Hashable {
    let id = UUID()
    let scanId: UUID?
    let image: UIImage
    let extractedData: ExtractedData
    let discogsMatches: [DiscogsMatch]
    let discogsError: String?
    let source: DetailNavigationSource

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ResultDestination, rhs: ResultDestination) -> Bool {
        lhs.id == rhs.id
    }
}

struct DetailDestination: Hashable {
    let id = UUID()
    let match: DiscogsMatch
    let scanId: UUID?
    let source: DetailNavigationSource

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DetailDestination, rhs: DetailDestination) -> Bool {
        lhs.id == rhs.id
    }
}

enum DetailNavigationSource: Hashable {
    case scanUtility
    case library
}

#Preview {
    ContentView()
}
