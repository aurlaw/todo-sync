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
    case categories

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let item): item.id.uuidString
        case .settings: "settings"
        case .categories: "categories"
        }
    }
}

/// "Added to Work" / "Moved to Work": shown when a save leaves the item outside the list on screen.
private struct FiledBanner: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let destination: CategorySelection
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
    /// Every row, deleted ones included; `CategoryTree` applies the display rule.
    @Query private var categories: [TodoCategory]

    @State private var category: Category? = .active
    @State private var selectedItemID: UUID?
    @State private var sheet: Sheet?
    /// This device's active category as stored, which may name a category that no longer resolves;
    /// `selection` is what is actually shown.
    @State private var activeCategoryID: UUID? = ActiveCategoryStore().storedID
    @State private var banner: FiledBanner?
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    private let secrets: any SecretStore = KeychainStore()

    private var store: TodoStore {
        TodoStore(context: modelContext, onMutation: { [coordinator] in
            coordinator.scheduleSync()
            WidgetReloader.reloadAll()
        })
    }

    private var tree: CategoryTree { CategoryTree(categories) }

    /// Falls back to Unassigned while the stored category does not resolve (deleted on the other
    /// device, or not pulled yet).
    private var selection: CategorySelection {
        ActiveCategoryStore.effectiveSelection(storedID: activeCategoryID, in: tree)
    }

    /// The active category's colour, or the app accent for Unassigned and uncoloured categories.
    private var tint: Color {
        CategoryColor.tint(for: tree.resolve(selection.categoryID)) ?? .appAccent
    }

    /// The active category first, then the sidebar rule. Active and All are the manually ordered
    /// lists; the rest sort by what defines them.
    private var visibleItems: [TodoItem] {
        let category = category ?? .active
        let (tree, selection) = (tree, selection)
        let filtered = items.filter { TodoFilter.isInCategory($0, selection, tree: tree) && category.includes($0) }
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
                TodoEditView(store: store, item: nil, tree: tree, defaultCategoryID: selection.categoryID, onSaved: didSave)
            case .existing(let item):
                TodoEditView(store: store, item: item, tree: tree, defaultCategoryID: nil, onSaved: didSave)
            case .settings:
                SettingsView(secrets: secrets, onManageCategories: { self.sheet = .categories })
            case .categories:
                CategoryManageView(store: store)
            }
        }
        // After `.sheet`, so the sheets take the category's colour too.
        .tint(tint)
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
        .environment(\.editMode, $editMode)
        .onChange(of: category) { editMode = .inactive }
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
            VStack(spacing: 0) {
                if let banner {
                    filedBanner(banner)
                }
                SyncStatusBanner(status: coordinator.status)
            }
        }
        .task(id: banner?.id) {
            guard banner != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { withAnimation { banner = nil } }
        }
        #if os(iOS)
        // A row of its own under the navigation bar, not a toolbar item: the bar's title slot has no room
        // left beside the four trailing buttons on an iPhone, and the switcher did not appear there.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                categoryMenu
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                categoryMenu
            }
            #endif
            ToolbarItem {
                SyncStatusButton(status: coordinator.status, accent: tint) {
                    Task { await coordinator.syncNow() }
                }
            }
            ToolbarItem {
                Button {
                    sheet = .new
                } label: {
                    Label("New", systemImage: "plus")
                        .foregroundStyle(.tint)
                }
                .keyboardShortcut("n")
                .tint(tint)
            }
            ToolbarItem {
                Button {
                    sheet = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .foregroundStyle(.tint)
                }
                .tint(tint)
            }
            #if os(iOS)
            // Drag handles appear in edit mode on iOS; macOS drags rows directly.
            if canReorder {
                // Not `EditButton`: it ignores button styles in an iOS 26 toolbar, so it can't be filled.
                ToolbarItem {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .accentFilled(tint)
                }
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
                tint: tint,
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

    private var categoryMenu: some View {
        CategoryMenu(
            tree: tree,
            counts: TodoFilter.dueCounts(items: items, tree: tree, now: .now, calendar: .current),
            selection: Binding(get: { selection }, set: { setActive($0) }),
            tint: tint,
            onManage: { sheet = .categories }
        )
    }

    private func filedBanner(_ banner: FiledBanner) -> some View {
        HStack {
            Text(banner.text)
                .font(.callout)
            Spacer()
            Button("Show") {
                setActive(banner.destination)
                self.banner = nil
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Switches this device's active category. A selected item that the new category does not show is deselected.
    private func setActive(_ newSelection: CategorySelection) {
        activeCategoryID = newSelection.categoryID
        ActiveCategoryStore().set(newSelection)
        if let selectedItem, !TodoFilter.isInCategory(selectedItem, newSelection, tree: tree) {
            selectedItemID = nil
        }
    }

    /// After the editor saves: if the item is no longer in the list on screen, say where it went.
    private func didSave(_ item: TodoItem, isNew: Bool) {
        let tree = tree
        guard !TodoFilter.isInCategory(item, selection, tree: tree) else { return }
        let destination = tree.resolve(item.categoryId)
        withAnimation {
            banner = FiledBanner(
                text: "\(isNew ? "Added to" : "Moved to") \(destination?.name ?? unassignedName)",
                destination: CategorySelection(destination?.id)
            )
        }
        if selectedItemID == item.id { selectedItemID = nil }
    }

    /// Where a widget or control tap lands. An unknown item id (deleted since the widget last drew) is ignored.
    /// `today` and `new` keep the active category; an item outside it switches to the item's own category first.
    private func open(_ link: DeepLink) {
        switch link {
        case .today:
            category = .today
            selectedItemID = nil
        case .new:
            sheet = .new
        case .item(let id):
            guard let item = items.first(where: { $0.id == id }) else { return }
            let tree = tree
            if !TodoFilter.isInCategory(item, selection, tree: tree) {
                setActive(CategorySelection(tree.resolve(item.categoryId)?.id))
            }
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

extension Color {
    /// The asset-catalog accent, named explicitly: iOS 26 toolbars draw their items monochrome
    /// and ignore the inherited accent, so toolbar buttons need it passed to `.tint`.
    static let appAccent = Color("AccentColor")
}

extension View {
    /// A toolbar button filled with `tint` (the active category's colour), with white text. An iOS 26
    /// toolbar ignores `.borderedProminent` and needs the glass style; macOS takes the bordered one.
    func accentFilled(_ tint: Color) -> some View {
        #if os(iOS)
        buttonStyle(.glassProminent).tint(tint)
        #else
        buttonStyle(.borderedProminent).tint(tint)
        #endif
    }
}

#Preview {
    let container = try! TodoContainer.make(inMemory: true)
    ContentView()
        .modelContainer(container)
        .environment(SyncCoordinator(engine: SyncEngine(modelContainer: container, client: URLSessionSyncClient(secrets: KeychainStore()))))
}
