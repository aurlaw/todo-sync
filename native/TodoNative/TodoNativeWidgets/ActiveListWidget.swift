import AppIntents
import SwiftUI
import TodoNativeCore
import WidgetKit

struct ActiveListWidget: Widget {
    let kind = "ActiveListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodoTimelineProvider()) { entry in
            ActiveListView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Active Todos")
        .description("Your open todos in the order you set. Tap the circle to complete one.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ActiveListView: View {
    let entry: TodoEntry
    @Environment(\.widgetFamily) private var family

    /// Tuned by eye for the two sizes; adjust in the previews below.
    private var rowLimit: Int { family == .systemLarge ? 7 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Active")
                .font(.headline)
                .foregroundStyle(.tint)

            if let problem = entry.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if entry.items.isEmpty {
                Label("Nothing to do", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.items.prefix(rowLimit)) { item in
                    ActiveRow(item: item)
                }
                let hidden = entry.items.count - rowLimit
                if hidden > 0 {
                    Text("+\(hidden) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActiveRow: View {
    let item: TodoSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CompleteTodoIntent(todoID: item.id)) {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Link(destination: DeepLink.item(item.id).url) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let dueAt = item.dueAt {
                        Text(dueAt, format: .dateTime.month(.abbreviated).day())
                            .font(.caption)
                            .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview("Medium", as: .systemMedium) {
    ActiveListWidget()
} timeline: {
    TodoEntry.sample
}

#Preview("Large", as: .systemLarge) {
    ActiveListWidget()
} timeline: {
    TodoEntry.sample
}
