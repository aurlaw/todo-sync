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
    case active
    case today
    case upcoming
    case all
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "Active"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .all: "All"
        case .done: "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .active: "circle"
        case .today: "sun.max"
        case .upcoming: "calendar"
        case .all: "tray.full"
        case .done: "checkmark.circle"
        }
    }

    /// Active is every item not yet completed, dated or not. Today includes overdue items;
    /// Today/Upcoming exclude completed ones. Active, Today and Upcoming are defined in
    /// `TodoFilter` (Core) so the widgets apply exactly the same rules.
    func includes(_ item: TodoItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        switch self {
        case .active:
            return TodoFilter.isActive(item)
        case .all:
            return true
        case .done:
            return item.isDone
        case .today:
            return TodoFilter.isDueTodayOrOverdue(item, now: now, calendar: calendar)
        case .upcoming:
            return TodoFilter.isUpcoming(item, now: now, calendar: calendar)
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncCoordinator.self) private var coordinator
    @Query(
        filter: #Predicate<TodoItem> { !$0.isSoftDeleted },
        sort: [SortDescriptor(\TodoItem.sortOrder), SortDescriptor(\TodoItem.createdAt, order: .reverse)]
    )
    private var items: [TodoItem]

    @State private var category: Category? = .active
    @State private var selectedItemID: UUID?
    @State private var sheet: Sheet?

    private let secrets: any SecretStore = KeychainStore()

    private var store: TodoStore {
        TodoStore(context: modelContext, onMutation: { [coordinator] in
            coordinator.scheduleSync()
            WidgetReloader.reloadAll()
        })
    }

    /// Active and All are the manually ordered lists; the rest sort by what defines them.
    private var visibleItems: [TodoItem] {
        let category = category ?? .active
        let filtered = items.filter { category.includes($0) }
        switch category {
        case .active, .all:
            return filtered.sorted(by: TodoItem.manualOrder)
        case .today, .upcoming:
            return filtered.sorted {
                let (lhs, rhs) = ($0.dueAt ?? .distantFuture, $1.dueAt ?? .distantFuture)
                return lhs != rhs ? lhs < rhs : TodoItem.manualOrder($0, $1)
            }
        case .done:
            return filtered.sorted {
                $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : TodoItem.manualOrder($0, $1)
            }
        }
    }

    private var canReorder: Bool {
        switch category ?? .active {
        case .active, .all: true
        case .today, .upcoming, .done: false
        }
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
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { coordinator.handleActive() }
        }
        .onOpenURL { url in
            if let link = DeepLink(url: url) { open(link) }
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
            Label {
                Text(category.title)
            } icon: {
                Image(systemName: category.systemImage)
                    .foregroundStyle(.tint)
            }
            .tag(category)
        }
        .navigationTitle("Todo")
    }

    private var itemList: some View {
        List(selection: $selectedItemID) {
            ForEach(visibleItems) { item in
                row(for: item)
                    .tag(item.id)
            }
            .onMove(perform: moveAction)
        }
        .navigationTitle((category ?? .active).title)
        #if os(iOS)
        // A large title renders blank on iPhone when the list is the launch screen (default
        // category preselected) and it has rows; inline shows reliably.
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if visibleItems.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "checklist")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SyncStatusBanner(status: coordinator.status)
        }
        .toolbar {
            ToolbarItem {
                SyncStatusButton(status: coordinator.status) {
                    Task { await coordinator.syncNow() }
                }
            }
            ToolbarItem {
                Button {
                    sheet = .new
                } label: {
                    Label("New", systemImage: "plus")
                }
                .keyboardShortcut("n")
            }
            ToolbarItem {
                Button {
                    sheet = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            #if os(iOS)
            // Drag handles appear in edit mode on iOS; macOS drags rows directly.
            if canReorder {
                ToolbarItem { EditButton() }
            }
            #endif
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
            if canReorder {
                Button("Move to Top") { try? store.moveToTop(item) }
            }
            Button("Delete", role: .destructive) { delete(item) }
        }
    }

    /// `nil` switches drag-to-reorder off for the lists that aren't manually ordered.
    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard canReorder else { return nil }
        return { source, destination in
            try? store.move(fromOffsets: source, toOffset: destination, in: visibleItems)
        }
    }

    /// Where a widget or control tap lands. An unknown item id (deleted since the widget last drew) is ignored.
    private func open(_ link: DeepLink) {
        switch link {
        case .today:
            category = .today
            selectedItemID = nil
        case .new:
            sheet = .new
        case .item(let id):
            guard let item = items.first(where: { $0.id == id }) else { return }
            category = item.isDone ? .done : .active
            selectedItemID = id
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
    let container = try! TodoContainer.make(inMemory: true)
    ContentView()
        .modelContainer(container)
        .environment(SyncCoordinator(engine: SyncEngine(modelContainer: container, client: URLSessionSyncClient(secrets: KeychainStore()))))
}
