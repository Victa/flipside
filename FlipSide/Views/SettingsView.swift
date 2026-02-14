//
//  SettingsView.swift
//  FlipSide
//
//  Settings view for managing API keys and Discogs account configuration.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // State for API keys
    @State private var openAIAPIKey: String = ""
    @State private var discogsPersonalToken: String = ""
    
    // State for UI feedback
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""
    @State private var saveAlertTitle = "Success"
    @State private var isSavingOpenAI = false
    @State private var isSavingDiscogs = false
    
    // KeychainService instance
    private let keychainService = KeychainService.shared
    
    var body: some View {
        NavigationStack {
            Form {
                // OpenAI API Key Section
                Section {
                    SecureField("Enter your OpenAI API key", text: $openAIAPIKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    
                    // Current Status
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
                    
                    // Save Button
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
                
                // Discogs Personal Access Token Section
                Section {
                    SecureField("Enter your Discogs token", text: $discogsPersonalToken)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    
                    // Current Status
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
                    
                    // Save Button
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
                
                // Clear All Keys Section
                Section {
                    Button(role: .destructive, action: clearAllKeys) {
                        HStack {
                            Spacer()
                            Text("Clear All Keys")
                            Spacer()
                        }
                    }
                    .disabled(keychainService.openAIAPIKey == nil && keychainService.discogsPersonalToken == nil)
                } footer: {
                    Text("This will remove both API keys from secure storage.")
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
                loadCurrentKeys()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCurrentKeys() {
        // Load existing keys from keychain (show placeholder text, not actual keys for security)
        if keychainService.openAIAPIKey != nil {
            openAIAPIKey = "" // Don't show actual key
        }
        if keychainService.discogsPersonalToken != nil {
            discogsPersonalToken = "" // Don't show actual token
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
                    
                    // Clear the text field after saving
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
                    
                    // Clear the text field after saving
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
            
            // Clear the text fields
            openAIAPIKey = ""
            discogsPersonalToken = ""
            
            saveAlertTitle = "Cleared"
            saveAlertMessage = "All API keys have been removed from secure storage."
            showingSaveAlert = true
        } catch {
            saveAlertTitle = "Error"
            saveAlertMessage = "Failed to clear keys: \(error.localizedDescription)"
            showingSaveAlert = true
        }
    }
}

#Preview {
    SettingsView()
}
