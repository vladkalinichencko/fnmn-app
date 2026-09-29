import FNMNCore
import SwiftUI
import UniformTypeIdentifiers

/// The one sheet, picker or alert a window shows over the library at a time.
enum LibraryDialog: Equatable {
    case none
    case addingLink(String)
    case pickingFile
    case namingAlbum(adding: String?)
    case renamingAlbum(String)
    case pickingAlbum(itemID: String)
    case confirmingDelete(itemID: String)
    case confirmingAlbumDelete(String)
    case settings
}

enum DialogAction {
    case addLink(String)
    case pickFile
    case nameAlbum(adding: String?)
    case renameAlbum(String)
    case pickAlbum(itemID: String)
    case confirmDelete(itemID: String)
    case confirmAlbumDelete(String)
    case openSettings
    case dismiss
}

func dialogReduce(_ dialog: LibraryDialog, _ action: DialogAction) -> LibraryDialog {
    switch action {
    case let .addLink(draft): .addingLink(draft)
    case .pickFile: .pickingFile
    case let .nameAlbum(itemID): .namingAlbum(adding: itemID)
    case let .renameAlbum(name): .renamingAlbum(name)
    case let .pickAlbum(itemID): .pickingAlbum(itemID: itemID)
    case let .confirmDelete(itemID): .confirmingDelete(itemID: itemID)
    case let .confirmAlbumDelete(name): .confirmingAlbumDelete(name)
    case .openSettings: .settings
    case .dismiss: .none
    }
}

@MainActor @Observable
final class LibraryDialogs {
    private(set) var dialog = LibraryDialog.none

    func send(_ action: DialogAction) {
        dialog = dialogReduce(dialog, action)
    }

    func isShowing(_ matches: @escaping (LibraryDialog) -> Bool) -> Binding<Bool> {
        Binding(get: { matches(self.dialog) }, set: { if !$0, matches(self.dialog) { self.send(.dismiss) } })
    }
}

extension View {
    func libraryDialogs() -> some View {
        modifier(LibraryDialogsModifier())
    }
}

private struct LibraryDialogsModifier: ViewModifier {
    @Environment(LibraryDialogs.self) private var dialogs
    @Environment(LibraryModel.self) private var library
    @Environment(ImportJobs.self) private var imports
    @State private var albumName = ""

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: dialogs.isShowing { if case .addingLink = $0 { true } else { false } }) {
                if case let .addingLink(draft) = dialogs.dialog {
                    LinkSheet(initial: draft)
                }
            }
            .fileImporter(
                isPresented: dialogs.isShowing { $0 == .pickingFile },
                allowedContentTypes: [.json, .pdf, .folder]
            ) { result in
                guard case let .success(url) = result else { return }
                imports.send(.submit(.file(url), id: UUID()))
            }
            .sheet(isPresented: dialogs.isShowing { if case .pickingAlbum = $0 { true } else { false } }) {
                if case let .pickingAlbum(itemID) = dialogs.dialog {
                    AlbumPicker(itemID: itemID)
                }
            }
            .sheet(isPresented: dialogs.isShowing { $0 == .settings }) {
                SettingsScreen()
            }
            .alert("New Album", isPresented: dialogs.isShowing { if case .namingAlbum = $0 { true } else { false } }, presenting: dialogs.dialog.albumTarget) { itemID in
                TextField("Name", text: $albumName)
                Button("Create") { createAlbum(adding: itemID) }
                Button("Cancel", role: .cancel) { albumName = "" }
            }
            .alert("Rename Album", isPresented: dialogs.isShowing { if case .renamingAlbum = $0 { true } else { false } }, presenting: dialogs.dialog.renamedAlbum) { name in
                TextField("Name", text: $albumName)
                Button("Rename") { rename(name) }
                Button("Cancel", role: .cancel) { albumName = "" }
            }
            .confirmationDialog(
                "Delete this material?",
                isPresented: dialogs.isShowing { if case .confirmingDelete = $0 { true } else { false } },
                titleVisibility: .visible,
                presenting: dialogs.dialog.deletedItem
            ) { itemID in
                Button("Delete", role: .destructive) { Task { await library.apply(.delete(itemID: itemID)) } }
            } message: { _ in
                Text("Its place, highlights and notes are deleted too.")
            }
            .confirmationDialog(
                "Delete this album?",
                isPresented: dialogs.isShowing { if case .confirmingAlbumDelete = $0 { true } else { false } },
                titleVisibility: .visible,
                presenting: dialogs.dialog.deletedAlbum
            ) { name in
                Button("Delete Album", role: .destructive) { Task { await library.apply(.deleteAlbum(name)) } }
            } message: { _ in
                Text("Materials stay in the library.")
            }
            .onChange(of: dialogs.dialog) { _, dialog in
                if case let .renamingAlbum(name) = dialog { albumName = name }
            }
    }

    private func createAlbum(adding itemID: String?) {
        let name = albumName
        albumName = ""
        Task {
            await library.apply(.createAlbum(name))
            if let itemID { await library.apply(.addToAlbum(name, itemIDs: [itemID])) }
        }
    }

    private func rename(_ name: String) {
        let newName = albumName
        albumName = ""
        Task { await library.apply(.renameAlbum(name, to: newName)) }
    }
}

/// The payload each alert keeps from the moment it was shown.
private extension LibraryDialog {
    /// `.some(nil)` is a new album on its own; `.some(id)` also adds that material to it.
    var albumTarget: String?? {
        if case let .namingAlbum(itemID) = self { itemID } else { nil }
    }

    var renamedAlbum: String? {
        if case let .renamingAlbum(name) = self { name } else { nil }
    }

    var deletedItem: String? {
        if case let .confirmingDelete(itemID) = self { itemID } else { nil }
    }

    var deletedAlbum: String? {
        if case let .confirmingAlbumDelete(name) = self { name } else { nil }
    }
}
