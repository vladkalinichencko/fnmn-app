import ActivityKit
import SwiftUI
import WidgetKit

/// A wait outside the app, such as a Mac copying materials in: one row the way a system activity reads, with
/// an icon, the title over the stage, and one ring for the share done. Imports show the system's own
/// continued-processing view instead, so nothing starts this activity for them.
struct ImportActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ImportActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.doc")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.headline)
                    Text(context.state.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Ring(fraction: context.state.fraction)
                    .frame(width: 28, height: 28)
            }
            .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.status)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        ShareDone(fraction: context.state.fraction)
                    }
                }
            } compactLeading: {
                Image(systemName: "arrow.down.doc")
            } compactTrailing: {
                ShareDone(fraction: context.state.fraction)
            } minimal: {
                ShareDone(fraction: context.state.fraction)
            }
        }
    }
}

/// A small ring in the Dynamic Island, the size of the icon beside it.
private struct ShareDone: View {
    let fraction: Double?

    var body: some View {
        Ring(fraction: fraction)
            .frame(width: 18, height: 18)
    }
}

/// The share done as a ring that fills; empty while the share is unknown. It takes exactly the frame it is given.
private struct Ring: View {
    let fraction: Double?

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.3), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction ?? 0)
                .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(1.5)
    }
}

@main
struct ImportActivityBundle: WidgetBundle {
    var body: some Widget {
        ImportActivityWidget()
        ContinueWidget()
        DigestWidget()
    }
}
