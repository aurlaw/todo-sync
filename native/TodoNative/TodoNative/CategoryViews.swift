//
//  CategoryViews.swift
//  TodoNative
//

import SwiftUI
import SwiftData
import TodoNativeCore

/// The name shown for the virtual category that has no row.
let unassignedName = "Unassigned"

extension CategoryTree {
    /// What a category is called in a picker: subcategories carry a leading marker, since a `Menu`
    /// can't indent its rows.
    func pickerTitle(for category: TodoCategory) -> String {
        isSubcategory(category) ? "↳ \(category.name)" : category.name
    }
}

/// The toolbar's category switcher: Unassigned, then each top-level category followed by its
/// subcategories, each with its due-today-or-overdue count, then the link to the manage screen.
struct CategoryMenu: View {
    let tree: CategoryTree
    let counts: CategoryDueCounts
    @Binding var selection: CategorySelection
    let tint: Color
    let onManage: () -> Void

    var body: some View {
        Menu {
            Picker("Category", selection: $selection) {
                Text(title(unassignedName, .unassigned)).tag(CategorySelection.unassigned)
                ForEach(tree.flattened, id: \.category.id) { entry in
                    let entrySelection = CategorySelection.category(entry.category.id)
                    Text(title(tree.pickerTitle(for: entry.category), entrySelection)).tag(entrySelection)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()
            Button("Manage Categories…", action: onManage)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                Text(tree.resolve(selection.categoryID)?.name ?? unassignedName)
                    .font(.headline)
                    .lineLimit(1)
                #if os(iOS)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                #endif
            }
        }
        .help("Switch category")
    }

    private func title(_ name: String, _ entry: CategorySelection) -> String {
        let count = counts[entry]
        return count > 0 ? "\(name) (\(count))" : name
    }
}

private enum CategoryEditTarget: Identifiable {
    case new
    case existing(TodoCategory)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let category): category.id.uuidString
        }
    }

    var category: TodoCategory? {
        switch self {
        case .new: nil
        case .existing(let category): category
        }
    }
}

/// Add, edit, reorder and delete categories. Unassigned is not listed: it has no row and can't change.
/// Each sibling group is its own section, because a row can only be dragged within its own group.
struct CategoryManageView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [TodoCategory]

    let store: TodoStore

    @State private var editing: CategoryEditTarget?
    @State private var pendingDelete: TodoCategory?
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    private var tree: CategoryTree { CategoryTree(categories) }

    var body: some View {
        let tree = tree
        NavigationStack {
            List {
                if !tree.topLevel.isEmpty {
                    Section {
                        ForEach(tree.topLevel) { category in
                            row(category, subcategories: tree.children(of: category.id).count)
                        }
                        .onMove { source, destination in
                            try? store.moveCategory(fromOffsets: source, toOffset: destination, in: tree.topLevel)
                        }
                    }
                }
                ForEach(tree.topLevel.filter { !tree.children(of: $0.id).isEmpty }) { parent in
                    let children = tree.children(of: parent.id)
                    Section("In \(parent.name)") {
                        ForEach(children) { category in
                            row(category, subcategories: 0)
                        }
                        .onMove { source, destination in
                            try? store.moveCategory(fromOffsets: source, toOffset: destination, in: children)
                        }
                    }
                }
            }
            #if os(iOS)
            .environment(\.editMode, $editMode)
            #endif
            .overlay {
                if tree.topLevel.isEmpty {
                    ContentUnavailableView(
                        "No categories",
                        systemImage: "folder",
                        description: Text("Everything is in \(unassignedName) until you add one.")
                    )
                }
            }
            .navigationTitle("Categories")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editing = .new
                    } label: {
                        Label("Add Category", systemImage: "plus")
                    }
                }
                #if os(iOS)
                // Drag handles appear in edit mode on iOS; macOS drags rows directly.
                if tree.topLevel.count > 1 || tree.flattened.contains(where: \.isSubcategory) {
                    ToolbarItem(placement: .primaryAction) {
                        Button(editMode.isEditing ? "Done Reordering" : "Reorder") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }
                    }
                }
                #endif
            }
            .sheet(item: $editing) { target in
                CategoryEditView(store: store, category: target.category, tree: tree)
            }
            .confirmationDialog(
                "Delete Category",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { category in
                Button("Delete \(category.name)", role: .destructive) {
                    try? store.deleteCategory(category)
                }
            } message: { category in
                Text(deletionMessage(for: category))
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func row(_ category: TodoCategory, subcategories: Int) -> some View {
        Button {
            editing = .existing(category)
        } label: {
            HStack {
                Circle()
                    .fill(CategoryColor.tint(for: category) ?? .appAccent)
                    .frame(width: 12, height: 12)
                Text(category.name)
                Spacer()
                if subcategories > 0 {
                    Text(subcategories == 1 ? "1 subcategory" : "\(subcategories) subcategories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            // Not `role: .destructive`: the row must stay until the confirmation is answered.
            Button {
                pendingDelete = category
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .contextMenu {
            Button("Edit…") { editing = .existing(category) }
            Button("Delete…", role: .destructive) { pendingDelete = category }
        }
    }

    /// "Work will be deleted. 3 subcategories become top-level; 8 items move to Unassigned."
    private func deletionMessage(for category: TodoCategory) -> String {
        let impact = (try? store.deletionImpact(of: category)) ?? (subcategories: 0, items: 0)
        var consequences: [String] = []
        if impact.subcategories == 1 {
            consequences.append("1 subcategory becomes top-level")
        } else if impact.subcategories > 1 {
            consequences.append("\(impact.subcategories) subcategories become top-level")
        }
        if impact.items == 1 {
            consequences.append("1 item moves to \(unassignedName)")
        } else if impact.items > 1 {
            consequences.append("\(impact.items) items move to \(unassignedName)")
        }
        let first = "\(category.name) will be deleted."
        return consequences.isEmpty ? first : "\(first) \(consequences.joined(separator: "; "))."
    }
}

/// Name, parent and colour for one category. The store validates on save; its refusal is shown inline.
struct CategoryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.self) private var environment

    let store: TodoStore
    let category: TodoCategory?
    let tree: CategoryTree

    @State private var name: String
    @State private var parentID: UUID?
    @State private var hasColor: Bool
    @State private var color: Color
    @State private var errorMessage: String?

    init(store: TodoStore, category: TodoCategory?, tree: CategoryTree) {
        self.store = store
        self.category = category
        self.tree = tree
        _name = State(initialValue: category?.name ?? "")
        _parentID = State(initialValue: category.flatMap { tree.parent(of: $0)?.id })
        _hasColor = State(initialValue: category?.color != nil)
        let stored = category?.color.flatMap(CategoryColor.parse)
        _color = State(initialValue: stored.map { Color($0) } ?? .blue)
    }

    /// One level only: a category that has subcategories can't become one.
    private var hasSubcategories: Bool {
        category.map { !tree.children(of: $0.id).isEmpty } ?? false
    }

    private var hex: String? {
        hasColor ? CategoryColor.hex(color.resolve(in: environment)) : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $name)
                        .labelsHidden()
                }

                Section {
                    Picker("Parent", selection: $parentID) {
                        Text("None").tag(UUID?.none)
                        ForEach(tree.parentCandidates(for: category)) { candidate in
                            Text(candidate.name).tag(UUID?.some(candidate.id))
                        }
                    }
                    .disabled(hasSubcategories)
                } footer: {
                    if hasSubcategories {
                        Text("A category that has subcategories can't be moved under another one.")
                    }
                }

                Section {
                    Toggle("Custom color", isOn: $hasColor)
                    if hasColor {
                        ColorPicker("Color", selection: $color, supportsOpacity: false)
                        if let light = hex.flatMap(CategoryColor.parse) {
                            preview(light: light)
                        }
                    }
                } footer: {
                    Text(hasColor
                         ? "The dark-mode color is worked out from this one so it stays readable."
                         : "Uses the app's accent color.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
    }

    /// The picked colour on white and its derived dark variant on the dark background, each with its
    /// contrast ratio and a warning below 4.5:1.
    private func preview(light: SRGB) -> some View {
        let dark = CategoryColor.darkVariant(of: light)
        return HStack(alignment: .top, spacing: 12) {
            swatch("Light", color: light, background: CategoryColor.lightBackground,
                   contrast: CategoryColor.contrastOnLight(light))
            swatch("Dark", color: dark, background: CategoryColor.darkBackground,
                   contrast: CategoryColor.contrastOnDark(dark))
        }
        .padding(.vertical, 4)
    }

    private func swatch(_ title: String, color: SRGB, background: SRGB, contrast: Double) -> some View {
        VStack(spacing: 6) {
            Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Category" : name)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(Color(color))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 8)
                .background(Color(background), in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            HStack(spacing: 4) {
                if contrast < CategoryColor.minimumContrast {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Below 4.5:1, text in this color is hard to read.")
                }
                Text("\(title) \(contrast, format: .number.precision(.fractionLength(1))):1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        do {
            if let category {
                try store.updateCategory(category, name: name, parentId: parentID, color: hex)
            } else {
                try store.createCategory(name: name, parentId: parentID, color: hex)
            }
            dismiss()
        } catch let error as CategoryError {
            errorMessage = error.description
        } catch {
            errorMessage = "Couldn't save the category: \(error)"
        }
    }
}
