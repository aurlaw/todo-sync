//
//  SettingsView.swift
//  TodoNative
//
//  Created by Michael Lawrence on 9/13/26.
//

import SwiftUI
import TodoNativeCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var coordinator

    let secrets: any SecretStore

    @State private var baseURL = ""
    @State private var token = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Worker base URL", text: $baseURL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                    SecureField("API token", text: $token)
                } footer: {
                    Text("Stored in the Keychain on this device. Saving runs a sync.")
                }

                Section {
                    Button("Reset sync (full re-pull)") {
                        Task { await coordinator.resetAndSync() }
                        dismiss()
                    }
                } footer: {
                    Text("Pulls everything from the server again using the saved URL and token. Local changes are pushed first and kept.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    LabeledContent("Version", value: Self.versionDescription)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    /// "1.0 (4)": `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from the built bundle's Info.plist.
    private static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func load() {
        baseURL = (try? secrets.get(.workerBaseURL)) ?? ""
        token = (try? secrets.get(.apiToken)) ?? ""
    }

    private func save() {
        do {
            try store(.workerBaseURL, baseURL)
            try store(.apiToken, token)
            Task { await coordinator.syncNow() }
            dismiss()
        } catch {
            errorMessage = "Could not save to the Keychain: \(error)"
        }
    }

    private func store(_ key: SecretKey, _ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try secrets.delete(key)
        } else {
            try secrets.set(key, value: trimmed)
        }
    }
}
