import SwiftUI
import TodoNativeCore

/// The sheet shown in the Share panel: an editable title, the note that will be saved with it, Add and Cancel.
struct ShareView: View {
    let draft: CaptureDraft
    let add: (CaptureDraft) -> Void
    let cancel: () -> Void

    @State private var title: String

    init(draft: CaptureDraft, add: @escaping (CaptureDraft) -> Void, cancel: @escaping () -> Void) {
        self.draft = draft
        self.add = add
        self.cancel = cancel
        _title = State(initialValue: draft.title)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title, axis: .vertical)
                }
                if let notes = draft.notes {
                    Section("Note") {
                        Text(notes)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                }
            }
            .navigationTitle("Add to Todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        add(CaptureDraft(title: trimmedTitle, notes: draft.notes))
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }
}

/// Shown instead of the sheet when there is nothing to save or the store isn't ready.
struct MessageView: View {
    let text: String
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Text(text)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Add to Todo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: close)
                    }
                }
        }
    }
}
