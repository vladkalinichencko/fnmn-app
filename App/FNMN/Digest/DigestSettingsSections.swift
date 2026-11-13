import FNMNCore
import SwiftUI

struct DigestSettingsSections: View {
    @Binding var settings: DigestSettings

    var body: some View {
        Group {
            Section("Build Times") {
                hourPicker("Morning", index: 0, fallback: 8)
                hourPicker("Evening", index: 1, fallback: 20)
            }
            ForEach(DigestPackage.Network.allCases, id: \.self) { network in
                Section(network.name) {
                    if network != .telegram {
                        Toggle("Include recommendations", isOn: recommendationsBinding(network))
                    }
                    NavigationLink {
                        TopicListScreen(title: "Topics", topics: networkTopicsBinding(network))
                    } label: {
                        LabeledContent("Topics", value: topicSummary(networkTopicsBinding(network).wrappedValue))
                    }
                }
            }
        }
    }

    private func hourPicker(_ title: String, index: Int, fallback: Int) -> some View {
        Picker(title, selection: hourBinding(index, fallback: fallback)) {
            ForEach(0..<24, id: \.self) { hour in
                Text("\(hour):00").tag(hour)
            }
        }
        .pickerStyle(.menu)
    }

    private func hourBinding(_ index: Int, fallback: Int) -> Binding<Int> {
        Binding(
            get: { settings.hours.count > index ? settings.hours[index] : fallback },
            set: { value in
                var hours = settings.hours
                while hours.count <= index {
                    hours.append(fallback)
                }
                hours[index] = value
                settings.hours = hours.sorted()
            }
        )
    }

    private func networkTopicsBinding(_ network: DigestPackage.Network) -> Binding<[String]> {
        Binding(
            get: { settings.networks[network.rawValue]?.topics ?? [] },
            set: { topics in
                var entry = settings.networks[network.rawValue] ?? DigestSettings.Network()
                entry.topics = topics
                settings.networks[network.rawValue] = entry == DigestSettings.Network() ? nil : entry
            }
        )
    }

    private func topicSummary(_ topics: [String]) -> String {
        topics.isEmpty ? "All posts" : topics.joined(separator: ", ")
    }

    private func recommendationsBinding(_ network: DigestPackage.Network) -> Binding<Bool> {
        Binding(
            get: { settings.networks[network.rawValue]?.recommendations ?? false },
            set: { value in
                var entry = settings.networks[network.rawValue] ?? DigestSettings.Network()
                entry.recommendations = value
                settings.networks[network.rawValue] = entry == DigestSettings.Network() ? nil : entry
            }
        )
    }
}

private struct TopicListScreen: View {
    let title: String
    var detail: String?
    @Binding var topics: [String]
    @State private var draft = ""

    var body: some View {
        List {
            if let detail {
                Section {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                TextField("Add a topic", text: $draft)
                    .onSubmit(commit)
            }
            Section("Topics") {
                ForEach(topics, id: \.self) { topic in
                    Text(topic)
                }
                .onDelete { topics.remove(atOffsets: $0) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func commit() {
        let topic = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !topic.isEmpty, !topics.contains(topic) else {
            return
        }
        topics.append(topic)
    }
}
