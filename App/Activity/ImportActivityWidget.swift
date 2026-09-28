import ActivityKit
import SwiftUI
import WidgetKit

struct ImportActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ImportActivityAttributes.self) { context in
            VStack(alignment: .leading) {
                Text(context.attributes.title)
                Text(context.state.status)
                ImportProgress(fraction: context.state.fraction)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.status)
                    ImportProgress(fraction: context.state.fraction)
                }
            } compactLeading: {
                Image(systemName: "arrow.down.doc")
            } compactTrailing: {
                ImportProgress(fraction: context.state.fraction)
            } minimal: {
                ImportProgress(fraction: context.state.fraction)
            }
        }
    }
}

private struct ImportProgress: View {
    let fraction: Double?

    var body: some View {
        if let fraction {
            ProgressView(value: fraction)
        } else {
            ProgressView()
        }
    }
}

@main
struct ImportActivityBundle: WidgetBundle {
    var body: some Widget {
        ImportActivityWidget()
    }
}
