import FNMNCore
import SwiftUI

struct DigestSettingsSections: View {
    @Binding var settings: DigestSettings
    @Environment(DigestModel.self) private var digests

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
            sourcesSections
        }
    }

    @ViewBuilder private var sourcesSections: some View {
        if let digest = digests.current {
            ForEach(folders(of: digest.package), id: \.folder) { group in
                Section(group.folder) {
                    ForEach(group.sources) { source in
                        NavigationLink {
                            TopicListScreen(title: source.name, detail: source.id, topics: sourceTopicsBinding(source.id))
                        } label: {
                            Text(source.name)
                        }
                    }
                }
            }
        }
    }

    private struct SourceGroup {
        let folder: String
        let sources: [DigestPackage.Source]
    }

    private func folders(of package: DigestPackage) -> [SourceGroup] {
        if package.folders.isEmpty {
            return DigestPackage.networkOrder.compactMap { network in
                let own = package.sources.filter { $0.network == network }
                return own.isEmpty ? nil : SourceGroup(folder: network.name, sources: own)
            }
        }
        return package.folders.map { folder in
            SourceGroup(folder: folder, sources: package.sources.filter { $0.folders.contains(folder) })
        }
        .filter { !$0.sources.isEmpty }
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

    private func sourceTopicsBinding(_ id: String) -> Binding<[String]> {
        Binding(
            get: { settings.sources[id]?.topics ?? [] },
            set: { topics in
                var entry = settings.sources[id] ?? DigestSettings.Source()
                entry.topics = topics
                settings.sources[id] = entry.topics.isEmpty ? nil : entry
            }
        )
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
