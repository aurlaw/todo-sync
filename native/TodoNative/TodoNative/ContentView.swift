//
//  ContentView.swift
//  TodoNative
//
//  Created by Michael Lawrence on 9/13/26.
//

import SwiftUI
import SwiftData
import TodoNativeCore

enum Category: String, CaseIterable, Identifiable {
    case today
    case upcoming
    case all
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .all: "All"
        case .done: "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .upcoming: "calendar"
        case .all: "tray.full"
        case .done: "checkmark.circle"
        }
    }

    /// Today includes overdue items; Today/Upcoming exclude completed ones.
    func includes(_ item: TodoItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .done:
            return item.isDone
        case .today:
            guard !item.isDone, let dueAt = item.dueAt else { return false }
            let startOfTomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
            return dueAt < startOfTomorrow
        case .upcoming:
            guard !item.isDone, let dueAt = item.dueAt else { return false }
            let startOfTomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
            return dueAt >= startOfTomorrow
        }
    }
}

private enum Sheet: Identifiable {
    case new
    case existing(TodoItem)
    case settings

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let item): item.id.uuidString
        case .settings: "settings"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<TodoItem> { !$0.isSoftDeleted },
        sort: \TodoItem.createdAt
    )
    private var items: [TodoItem]

    @State private var category: Category? = .all
    @State private var selectedItemID: UUID?
    @State private var sheet: Sheet?

    private let secrets: any SecretStore = KeychainStore()

    private var store: TodoStore { TodoStore(context: modelContext) }

    private var visibleItems: [TodoItem] {
        let category = category ?? .all
        return items.filter { category.includes($0) }
    }

    private var selectedItem: TodoItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            itemList
        } detail: {
            detail
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .new:
                TodoEditView(store: store, item: nil)
            case .existing(let item):
                TodoEditView(store: store, item: item)
            case .settings:
                SettingsView(secrets: secrets)
            }
        }
    }

    private var sidebar: some View {
        List(Category.allCases, selection: $category) { category in
            Label(category.title, systemImage: category.systemImage)
                .tag(category)
        }
        .navigationTitle("Todo")
        .toolbar {
            ToolbarItem {
                Button {
                    sheet = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }

    private var itemList: some View {
        List(visibleItems, selection: $selectedItemID) { item in
            row(for: item)
                .tag(item.id)
        }
        .navigationTitle((category ?? .all).title)
        .overlay {
            if visibleItems.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "checklist")
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    sheet = .new
                } label: {
                    Label("New", systemImage: "plus")
                }
                .keyboardShortcut("n")
            }
        }
        #if os(macOS)
        .onDeleteCommand {
            if let selectedItem { delete(selectedItem) }
        }
        #endif
    }

    @ViewBuilder
    private var detail: some View {
        if let item = selectedItem {
            TodoDetailView(
                item: item,
                onToggleDone: { try? store.complete(item, isDone: !item.isDone) },
                onEdit: { sheet = .existing(item) },
                onDelete: { delete(item) }
            )
        } else {
            ContentUnavailableView("Select a todo", systemImage: "sidebar.right")
        }
    }

    private func row(for item: TodoItem) -> some View {
        HStack {
            Button {
                try? store.complete(item, isDone: !item.isDone)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading) {
                Text(item.title)
                    .strikethrough(item.isDone)
                if let dueAt = item.dueAt {
                    Text(dueAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(isOverdue(item, dueAt) ? .red : .secondary)
                }
            }

            Spacer()

            if item.recurrence != nil {
                Image(systemName: "repeat")
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                try? store.complete(item, isDone: !item.isDone)
            } label: {
                Label(item.isDone ? "Undo" : "Complete", systemImage: "checkmark")
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(item.isDone ? "Mark Not Done" : "Mark Done") {
                try? store.complete(item, isDone: !item.isDone)
            }
            Button("Edit…") { sheet = .existing(item) }
            Button("Delete", role: .destructive) { delete(item) }
        }
    }

    private func isOverdue(_ item: TodoItem, _ dueAt: Date) -> Bool {
        !item.isDone && dueAt < .now
    }

    private func delete(_ item: TodoItem) {
        try? store.softDelete(item)
        if selectedItemID == item.id { selectedItemID = nil }
    }
}

#Preview {
    ContentView()
        .modelContainer(try! TodoContainer.make(inMemory: true))
}
