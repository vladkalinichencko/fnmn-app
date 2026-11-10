import FNMNCore
import SwiftUI
import UniformTypeIdentifiers

/// The one sheet, picker or alert a window shows over the library at a time.
enum LibraryDialog: Equatable {
    case none
    case addingLink(String)
    case pickingFile
    case namingAlbum(adding: String?, draft: String)
    case renamingAlbum(name: String, draft: String)
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
    case typeAlbumName(String)
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
    case let .nameAlbum(itemID): .namingAlbum(adding: itemID, draft: "")
    case let .renameAlbum(name): .renamingAlbum(name: name, draft: name)
    case let .typeAlbumName(text):
        switch dialog {
        case let .namingAlbum(adding, _): .namingAlbum(adding: adding, draft: text)
        case let .renamingAlbum(name, _): .renamingAlbum(name: name, draft: text)
        default: dialog
        }
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

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: dialogs.isShowing { if case .addingLink = $0 { true } else { false } }) {
                if case let .addingLink(draft) = dialogs.dialog {
                    LinkSheet(initial: draft)
                }
            }
            .fileImporter(
                isPresented: dialogs.isShowing { $0 == .pickingFile },
                allowedContentTypes: [.item]
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
                    .presentationDetents([.medium, .large])
            }
            .alert("New Collection", isPresented: dialogs.isShowing { if case .namingAlbum = $0 { true } else { false } }, presenting: dialogs.dialog.albumTarget) { itemID in
                TextField("Name", text: draftBinding)
                Button("Create") { createAlbum(adding: itemID) }
                Button("Cancel", role: .cancel) { dialogs.send(.dismiss) }
            }
            .alert("Rename Collection", isPresented: dialogs.isShowing { if case .renamingAlbum = $0 { true } else { false } }, presenting: dialogs.dialog.renamedAlbum) { name in
                TextField("Name", text: draftBinding)
                Button("Rename") { rename(name) }
                Button("Cancel", role: .cancel) { dialogs.send(.dismiss) }
            }
            .confirmationDialog(
                "Delete this item?",
                isPresented: dialogs.isShowing { if case .confirmingDelete = $0 { true } else { false } },
                titleVisibility: .visible,
                presenting: dialogs.dialog.deletedItem
            ) { itemID in
                Button("Delete", role: .destructive) {
                    imports.send(.deleted(itemID: itemID))
                    Task { await library.apply(.delete(itemID: itemID)) }
                }
            } message: { _ in
                Text("Its place, highlights and notes are deleted too.")
            }
            .confirmationDialog(
                "Delete this collection?",
                isPresented: dialogs.isShowing { if case .confirmingAlbumDelete = $0 { true } else { false } },
                titleVisibility: .visible,
                presenting: dialogs.dialog.deletedAlbum
            ) { name in
                Button("Delete Collection", role: .destructive) { Task { await library.apply(.deleteAlbum(name)) } }
            } message: { _ in
                Text("Items stay in the library.")
            }
    }

    private var draftBinding: Binding<String> {
        Binding(get: { dialogs.dialog.draft }, set: { dialogs.send(.typeAlbumName($0)) })
    }

    private func createAlbum(adding itemID: String?) {
        let name = dialogs.dialog.draft
        Task {
            await library.apply(.createAlbum(name))
            if let itemID { await library.apply(.addToAlbum(name, itemIDs: [itemID])) }
        }
    }

    private func rename(_ name: String) {
        let newName = dialogs.dialog.draft
        Task { await library.apply(.renameAlbum(name, to: newName)) }
    }
}

/// The payload each alert keeps from the moment it was shown.
private extension LibraryDialog {
    var draft: String {
        switch self {
        case let .namingAlbum(_, draft), let .renamingAlbum(_, draft): draft
        default: ""
        }
    }

    /// `.some(nil)` is a new album on its own; `.some(id)` also adds that material to it.
    var albumTarget: String?? {
        if case let .namingAlbum(itemID, _) = self {
            return itemID
        }
        return nil
    }

    var renamedAlbum: String? {
        if case let .renamingAlbum(name, _) = self {
            return name
        }
        return nil
    }

    var deletedItem: String? {
        if case let .confirmingDelete(itemID) = self { itemID } else { nil }
    }

    var deletedAlbum: String? {
        if case let .confirmingAlbumDelete(name) = self { name } else { nil }
    }
}
