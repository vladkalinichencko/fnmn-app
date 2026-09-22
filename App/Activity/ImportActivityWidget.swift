import ActivityKit
import SwiftUI
import WidgetKit

struct ImportActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ImportActivityAttributes.self) { context in
            VStack(alignment: .leading) {
                Text(context.attributes.title)
                Text(context.state.status)
                ProgressView(value: context.state.fraction)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.status)
                    ProgressView(value: context.state.fraction)
                }
            } compactLeading: {
                Image(systemName: "arrow.down.doc")
            } compactTrailing: {
                ProgressView(value: context.state.fraction)
            } minimal: {
                ProgressView(value: context.state.fraction)
            }
        }
    }
}

@main
struct ImportActivityBundle: WidgetBundle {
    var body: some Widget {
        ImportActivityWidget()
    }
}
