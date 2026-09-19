//
//  SyncStatusViews.swift
//  TodoNative
//
//  Created by Michael Lawrence on 9/13/26.
//

import SwiftUI
import TodoNativeCore

/// Toolbar control: shows sync state and runs a sync when clicked (⌘R).
struct SyncStatusButton: View {
    let status: SyncStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch status {
            case .syncing:
                ProgressView().controlSize(.small)
            case .idle:
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            case .notConfigured:
                Label("Sync not configured", systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.secondary)
            case .failed:
                Label("Sync failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .keyboardShortcut("r")
        .disabled(status == .syncing)
        .help(helpText)
    }

    private var helpText: String {
        switch status {
        case .syncing: "Syncing…"
        case .idle(let lastSync):
            lastSync.map { "Sync now. Last synced \($0.formatted(.relative(presentation: .named)))." } ?? "Sync now"
        case .notConfigured: "Add the Worker URL and token in Settings to enable sync."
        case .failed(let message): message
        }
    }
}

/// A one-line message under the list for states the toolbar icon alone can't explain (notably on iPhone).
struct SyncStatusBanner: View {
    let status: SyncStatus

    var body: some View {
        switch status {
        case .notConfigured:
            banner("Sync is off. Add the Worker URL and token in Settings.", color: .secondary)
        case .failed(let message):
            banner(message, color: .red)
        default:
            EmptyView()
        }
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
    }
}
