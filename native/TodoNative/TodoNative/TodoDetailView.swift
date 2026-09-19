//
//  TodoDetailView.swift
//  TodoNative
//
//  Created by Michael Lawrence on 9/13/26.
//

import SwiftUI
import TodoNativeCore

struct TodoDetailView: View {
    let item: TodoItem
    let onToggleDone: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                Text(item.title)
                    .font(.title2)
                    .strikethrough(item.isDone)
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .foregroundStyle(.secondary)
                }
            }

            if item.dueAt != nil || item.recurrence != nil {
                Section {
                    if let dueAt = item.dueAt {
                        LabeledContent("Due") {
                            Text(dueAt, format: .dateTime.year().month().day().hour().minute())
                        }
                    }
                    if let recurrence = item.recurrence {
                        LabeledContent("Repeats", value: recurrence.summary)
                    }
                }
            }

            Section {
                Button(item.isDone ? "Mark Not Done" : "Mark Done", action: onToggleDone)
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Todo")
        .toolbar {
            ToolbarItem {
                Button("Edit", action: onEdit)
            }
        }
    }
}

extension RecurrenceRule {
    var summary: String {
        let unit: String
        switch frequency {
        case .daily: unit = interval == 1 ? "day" : "days"
        case .weekly: unit = interval == 1 ? "week" : "weeks"
        case .monthly: unit = interval == 1 ? "month" : "months"
        }
        return interval == 1 ? "Every \(unit)" : "Every \(interval) \(unit)"
    }
}
