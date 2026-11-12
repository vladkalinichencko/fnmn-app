import FNMNCore
import SwiftUI

struct SourcesScreen: View {
    @Environment(DigestModel.self) private var digests

    var body: some View {
        ScrollView {
            if let digest = digests.current {
                VStack(alignment: .leading, spacing: Tokens.sectionGap) {
                    ForEach(folders(of: digest.package), id: \.folder) { group in
                        LibrarySection(group.folder.uppercased()) {
                            VStack(spacing: 8) {
                                ForEach(group.sources) { source in
                                    row(source)
                                }
                            }
                        }
                    }
                    Text("The Mac reads \(digest.package.sources.count) sources in these folders.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, Tokens.sectionGap)
            } else {
                ContentUnavailableView("No digest yet", systemImage: "newspaper")
            }
        }
        .modifier(ReaderAppearanceModifier())
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ source: DigestPackage.Source) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color(of: source.status))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.subheadline)
                Text(detail(of: source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(source.network == .telegram ? "Channel" : "Account")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(Tokens.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plate(cornerRadius: Tokens.plateRadius)
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

    private struct Group {
        let folder: String
        let sources: [DigestPackage.Source]
    }

    private func folders(of package: DigestPackage) -> [Group] {
        package.folders.map { folder in
            Group(folder: folder, sources: package.sources.filter { $0.folders.contains(folder) })
        }
        .filter { !$0.sources.isEmpty }
    }
}
