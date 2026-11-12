import FNMNCore
import SwiftUI

struct DigestSettingsScreen: View {
    @Environment(LibraryModel.self) private var library
    @Environment(DigestModel.self) private var digests
    @State private var settings = DigestSettings()

    var body: some View {
        Form {
            Section {
                Toggle("Collect digests", isOn: binding(\.enabled))
            }
            Section("Build times") {
                Picker("Morning", selection: hourBinding(0, fallback: 8)) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text("\(hour):00").tag(hour)
                    }
                }
                Picker("Evening", selection: hourBinding(1, fallback: 20)) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text("\(hour):00").tag(hour)
                    }
                }
            }
            Section("Selection") {
                Stepper("Up to \(settings.limit) posts", value: binding(\.limit), in: 10...300, step: 10)
                VStack(alignment: .leading) {
                    LabeledContent("Topic match") {
                        Text(settings.threshold, format: .percent.precision(.fractionLength(2)))
                    }
                    Slider(value: binding(\.threshold), in: 0.1...0.9)
                }
            }
            ForEach(DigestPackage.Network.allCases, id: \.self) { network in
                Section(network.name) {
                    if network != .telegram {
                        Toggle("Include recommendations", isOn: recommendationsBinding(network))
                    }
                    TopicEditor(topics: networkTopicsBinding(network))
                    let found = sources(of: network)
                    if !found.isEmpty {
                        DisclosureGroup("Sources (\(found.count))") {
                            ForEach(found) { source in
                                SourceTopicsRow(source: source, topics: sourceTopicsBinding(source.id))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Digest Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let folder = library.cloudFolder {
                settings = DigestSettings.load(from: folder)
            }
        }
        .onChange(of: settings) {
            guard let folder = library.cloudFolder else {
                return
            }
            try? settings.save(to: folder)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<DigestSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
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

    private func networkBinding(_ network: DigestPackage.Network) -> Binding<DigestSettings.Network> {
        Binding(
            get: { settings.networks[network.rawValue] ?? DigestSettings.Network() },
            set: { value in
                settings.networks[network.rawValue] = value == DigestSettings.Network() ? nil : value
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

    private func sourceTopicsBinding(_ id: String) -> Binding<[String]> {
        Binding(
            get: { settings.sources[id]?.topics ?? [] },
            set: { topics in
                var entry = settings.sources[id] ?? DigestSettings.Source()
                entry.topics = topics
                settings.sources[id] = entry == DigestSettings.Source() ? nil : entry
            }
        )
    }

    private func sources(of network: DigestPackage.Network) -> [DigestPackage.Source] {
        var seen = Set<String>()
        var found: [DigestPackage.Source] = []
        for digest in digests.digests {
            for source in digest.package.sources where source.network == network && !seen.contains(source.id) {
                seen.insert(source.id)
                found.append(source)
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct TopicEditor: View {
    @Binding var topics: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !topics.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(topics, id: \.self) { topic in
                        HStack(spacing: 4) {
                            Text(topic)
                                .lineLimit(1)
                            Button {
                                topics.removeAll { $0 == topic }
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .font(.caption2)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    }
                }
            }
            TextField(topics.isEmpty ? "Add a topic" : "Add another", text: $draft)
                .onSubmit(commit)
        }
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

private struct SourceTopicsRow: View {
    let source: DigestPackage.Source
    @Binding var topics: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.name)
                .font(.subheadline)
            TextField(topics.isEmpty ? "Topics, comma separated" : topics.joined(separator: ", "), text: $draft)
                .font(.caption)
                .foregroundStyle(topics.isEmpty ? .secondary : .primary)
                .onSubmit(commit)
        }
        .onAppear { draft = topics.joined(separator: ", ") }
    }

    private func commit() {
        topics = draft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
