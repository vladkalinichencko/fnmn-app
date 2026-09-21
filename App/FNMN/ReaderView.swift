import SwiftUI

struct ReaderView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    let package: ImportPackage
    @State private var index = 0
    @State private var showingOutline = false
    @State private var showingNote = false

    var body: some View {
        Group {
            if package.blocks.isEmpty {
                ContentUnavailableView("This material has no readable blocks", systemImage: "doc")
            } else {
                VStack {
                    blockView(package.blocks[index])
                    Divider()
                    HStack {
                        Button("Previous", systemImage: "chevron.left") { move(to: index - 1) }.disabled(index == 0)
                        Spacer()
                        Text("\(index + 1) of \(package.blocks.count)").foregroundStyle(.secondary)
                        Spacer()
                        Button("Next", systemImage: "chevron.right") { move(to: index + 1) }.disabled(index + 1 == package.blocks.count)
                    }
                    .padding()
                }
                .gesture(MagnifyGesture().onEnded {
                    value in if value.magnification < 0.8 {
                        showingOutline = true
                    }
                })
            }
        }
        .navigationTitle(package.material.title)
        .toolbar {
            Button("Sections", systemImage: "list.bullet.indent") { showingOutline = true }
            Button(currentNote == nil ? "Add note" : "Edit note", systemImage: "note.text.badge.plus") { showingNote = true }
            Link("Source", destination: package.material.sourceURL)
        }
        .sheet(isPresented: $showingOutline) {
            NavigationStack {
                List(package.sections) { section in
                    Button { open(blockID: section.firstBlockID); showingOutline = false } label: {
                        Text(section.title).padding(.leading, CGFloat(max(0, section.level - 1)) * 12)
                    }
                }.navigationTitle("Sections")
            }
        }
        .sheet(isPresented: $showingNote) {
            NoteEditor(package: package, block: package.blocks[index], initialText: currentNote?.text ?? "")
        }
        .task { restore() }
    }

    private var currentNote: Note? {
        let blockID = package.blocks[index].id
        return library.snapshot.notes.first { $0.materialID == package.material.id && $0.blockID == blockID }
    }

    private func restore() {
        guard let position = library.snapshot.positions[package.material.id] else { return }
        guard let target = package.blocks.firstIndex(where: { $0.id == position.blockID }) else { return }
        index = target
    }

    private func open(blockID: String) {
        guard let target = package.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        move(to: target)
    }

    private func move(to target: Int) {
        guard package.blocks.indices.contains(target) else { return }
        index = target
        Task { await library.save(position: ReadingPosition(blockID: package.blocks[target].id), materialID: package.material.id) }
    }

    private func blockView(_ block: Block) -> some View {
        BlockWebView(
            block: block,
            sourceURL: package.material.sourceURL,
            resumeSeconds: library.snapshot.positions[package.material.id]?.videoSeconds,
            scenePhase: scenePhase,
        ) { seconds in
            Task { await library.saveVideoTime(seconds, materialID: package.material.id, blockID: block.id) }
        }
        .id(block.id)
    }
}

private struct NoteEditor: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    let package: ImportPackage
    let block: Block
    @State private var text: String
    @State private var errorMessage: String?
    @State private var saving = false

    init(package: ImportPackage, block: Block, initialText: String) {
        self.package = package
        self.block = block
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form { TextEditor(text: $text).frame(minHeight: 180) }
                .navigationTitle("Note")
                .toolbar {
                    Button("Cancel") { dismiss() }.disabled(saving)
                    Button("Save") {
                        saving = true
                        Task {
                            do {
                                try await library.save(note: text, materialID: package.material.id, blockID: block.id)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                saving = false
                            }
                        }
                    }
                    .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
        }
        .alert("Save failed", isPresented: .init(get: { errorMessage != nil }, set: {
            if !$0 {
                errorMessage = nil
            }
        })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}
