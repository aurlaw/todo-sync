//
//  TodoEditView.swift
//  TodoNative
//
//  Created by Michael Lawrence on 9/13/26.
//

import SwiftUI
import TodoNativeCore

struct TodoEditView: View {
    @Environment(\.dismiss) private var dismiss

    let store: TodoStore
    let item: TodoItem?

    @State private var title: String
    @State private var notes: String
    @State private var hasDueDate: Bool
    @State private var dueAt: Date
    @State private var repeats: Bool
    @State private var frequency: Frequency
    @State private var interval: Int

    init(store: TodoStore, item: TodoItem?) {
        self.store = store
        self.item = item
        _title = State(initialValue: item?.title ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _hasDueDate = State(initialValue: item?.dueAt != nil)
        _dueAt = State(initialValue: item?.dueAt ?? .now)
        _repeats = State(initialValue: item?.recurrence != nil)
        _frequency = State(initialValue: item?.recurrence?.frequency ?? .daily)
        _interval = State(initialValue: item?.recurrence?.interval ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                        .labelsHidden()
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                Section {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueAt)
                            .datePickerStyle(.compact)
                    }
                }

                Section {
                    Toggle("Repeats", isOn: $repeats)
                    if repeats {
                        Picker("Frequency", selection: $frequency) {
                            Text("Daily").tag(Frequency.daily)
                            Text("Weekly").tag(Frequency.weekly)
                            Text("Monthly").tag(Frequency.monthly)
                        }
                        Stepper("Every \(interval) \(unitLabel)", value: $interval, in: 1...30)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(item == nil ? "New Todo" : "Edit Todo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 500)
        #endif
    }

    private var unitLabel: String {
        switch frequency {
        case .daily: "day(s)"
        case .weekly: "week(s)"
        case .monthly: "month(s)"
        }
    }

    private func save() {
        let resolvedDueAt = hasDueDate ? dueAt : nil
        let resolvedRecurrence = repeats ? RecurrenceRule(frequency: frequency, interval: interval) : nil
        let resolvedNotes = notes.isEmpty ? nil : notes

        do {
            if let item {
                try store.update(item, title: title, notes: resolvedNotes, dueAt: resolvedDueAt, recurrence: resolvedRecurrence)
            } else {
                try store.create(title: title, notes: resolvedNotes, dueAt: resolvedDueAt, recurrence: resolvedRecurrence)
            }
            dismiss()
        } catch {
            assertionFailure("Failed to save todo: \(error)")
        }
    }
}
