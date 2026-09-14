//
//  ContentView.swift
//  TodoNative
//
//  Created by Michael Lawrence on 9/13/26.
//

import SwiftUI
import SwiftData
import TodoNativeCore

private enum EditorTarget: Identifiable {
    case new
    case existing(TodoItem)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let item): item.id.uuidString
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

    @State private var editorTarget: EditorTarget?

    private var store: TodoStore { TodoStore(context: modelContext) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    row(for: item)
                }
            }
            .navigationTitle("Todo")
            .toolbar {
                ToolbarItem {
                    Button {
                        editorTarget = .new
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                switch target {
                case .new:
                    TodoEditView(store: store, item: nil)
                case .existing(let item):
                    TodoEditView(store: store, item: item)
                }
            }
        }
    }

    private func row(for item: TodoItem) -> some View {
        HStack {
            Button {
                try? store.complete(item, isDone: !item.isDone)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading) {
                Text(item.title)
                    .strikethrough(item.isDone)
                if let dueAt = item.dueAt {
                    Text(dueAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editorTarget = .existing(item)
        }
        .swipeActions {
            Button(role: .destructive) {
                try? store.softDelete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(try! TodoContainer.make(inMemory: true))
}
