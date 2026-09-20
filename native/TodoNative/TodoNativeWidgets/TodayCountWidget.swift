import SwiftUI
import TodoNativeCore
import WidgetKit

struct TodayCountWidget: Widget {
    let kind = "TodayCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodoTimelineProvider()) { entry in
            TodayCountView(entry: entry)
                .widgetURL(DeepLink.today.url)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Due Today")
        .description("How many todos are due today or overdue. Tap to open Today.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryCircular, .accessoryRectangular]
        #else
        [.systemSmall]
        #endif
    }
}

struct TodayCountView: View {
    let entry: TodoEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.dueCount)")
                        .font(.title2.bold())
                    Image(systemName: "sun.max")
                        .font(.caption2)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Due today")
                    .font(.headline)
                Text(summary)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("Today", systemImage: "sun.max")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                if let problem = entry.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(entry.dueCount)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("due or overdue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var summary: String {
        if let problem = entry.problem { return problem }
        switch entry.dueCount {
        case 0: return "Nothing due"
        case 1: return "1 todo due or overdue"
        default: return "\(entry.dueCount) todos due or overdue"
        }
    }
}

#Preview("Small", as: .systemSmall) {
    TodayCountWidget()
} timeline: {
    TodoEntry.sample
}
