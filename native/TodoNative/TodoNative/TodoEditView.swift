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
    let tree: CategoryTree
    /// Called after a successful save with the item and whether it is new.
    let onSaved: (TodoItem, Bool) -> Void

    /// What the category picker showed when the sheet opened: an existing item's resolved category.
    private let originalCategoryID: UUID?
    @State private var categoryID: UUID?
    @State private var title: String
    @State private var notes: String
    @State private var hasDueDate: Bool
    @State private var dueAt: Date
    @State private var repeats: Bool
    @State private var frequency: Frequency
    @State private var interval: Int

    /// A new item starts in `defaultCategoryID` (the active category); an existing one shows its own.
    init(
        store: TodoStore,
        item: TodoItem?,
        tree: CategoryTree,
        defaultCategoryID: UUID?,
        onSaved: @escaping (TodoItem, Bool) -> Void
    ) {
        self.store = store
        self.item = item
        self.tree = tree
        self.onSaved = onSaved
        let shown = item.map { tree.resolve($0.categoryId)?.id } ?? defaultCategoryID
        originalCategoryID = shown
        _categoryID = State(initialValue: shown)
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
                    Picker("Category", selection: $categoryID) {
                        Text(unassignedName).tag(UUID?.none)
                        ForEach(tree.flattened, id: \.category.id) { entry in
                            Text(tree.pickerTitle(for: entry.category)).tag(UUID?.some(entry.category.id))
                        }
                    }
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
                        .buttonStyle(.borderedProminent)
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
                // An untouched picker keeps the stored id as it is, even one that no longer resolves.
                let resolvedCategoryID = categoryID == originalCategoryID ? item.categoryId : categoryID
                try store.update(
                    item, title: title, notes: resolvedNotes, dueAt: resolvedDueAt,
                    recurrence: resolvedRecurrence, categoryId: resolvedCategoryID
                )
                onSaved(item, false)
            } else {
                let created = try store.create(
                    title: title, notes: resolvedNotes, dueAt: resolvedDueAt,
                    recurrence: resolvedRecurrence, categoryId: categoryID
                )
                onSaved(created, true)
            }
            dismiss()
        } catch {
            assertionFailure("Failed to save todo: \(error)")
        }
    }
}
