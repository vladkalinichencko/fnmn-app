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
                    TopicEditor(topics: networkTopicsBinding(network))
                }
            }
            sourcesSections
        }
    }

    @ViewBuilder private var sourcesSections: some View {
        if let digest = digests.current {
            ForEach(folders(of: digest.package), id: \.folder) { group in
                Section(group.folder.uppercased()) {
                    ForEach(group.sources) { source in
                        row(source)
                    }
                }
            }
        } else {
            Section("Sources") {
                Text("No digest yet")
                    .foregroundStyle(.secondary)
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

    private func row(_ source: DigestPackage.Source) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color(of: source.status))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                Text(detail(of: source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(source.network == .telegram ? "Channel" : "Account")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func detail(of source: DigestPackage.Source) -> String {
        switch source.status {
        case .ok: source.id
        case .stale: "Partially read: \(source.detail ?? "the network answered slowly")"
        case .failed: "Not read: \(source.detail ?? "the source failed")"
        }
    }

    private func color(of status: DigestPackage.Source.Status) -> Color {
        switch status {
        case .ok: .green
        case .stale: .orange
        case .failed: .red
        }
    }

    private struct SourceGroup {
        let folder: String
        let sources: [DigestPackage.Source]
    }

    private func folders(of package: DigestPackage) -> [SourceGroup] {
        package.folders.map { folder in
            SourceGroup(folder: folder, sources: package.sources.filter { $0.folders.contains(folder) })
        }
        .filter { !$0.sources.isEmpty }
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

private struct TopicEditor: View {
    @Binding var topics: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Add a topic", text: $draft)
                .font(.subheadline)
                .onSubmit(commit)
            ForEach(topics, id: \.self) { topic in
                HStack {
                    Text(topic)
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Button {
                        topics.removeAll { $0 == topic }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
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
