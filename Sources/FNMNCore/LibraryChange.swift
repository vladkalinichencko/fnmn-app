import Foundation

/// Every change a reader can make to the catalog; reading progress changes through `ProgressChange`.
/// A new change is a new case here and one branch in `applying`.
public enum LibraryChange: Equatable, Sendable {
    case setArchived(Bool, itemID: String)
    case createAlbum(String)
    case renameAlbum(String, to: String)
    case deleteAlbum(String)
    case addToAlbum(String, itemIDs: [String])
    case removeFromAlbum(String, itemID: String)
    case mark(TextMark, AnnotationTarget)
    case unmark(TextMark, AnnotationTarget)
    case note(String, AnnotationTarget)
    case removeAnnotation(UUID)
    case removeVideoFile(itemID: String)
    case delete(itemID: String)
}

extension LibrarySnapshot {
    public func applying(_ change: LibraryChange, at date: Date = .now) throws -> LibrarySnapshot {
        var next = self
        switch change {
        case let .setArchived(isArchived, itemID):
            next.archived.removeAll { $0 == itemID }
            if isArchived { next.archived.append(itemID) }
        case let .createAlbum(name):
            next.albums.append(try next.freshAlbumName(name))
        case let .renameAlbum(name, newName):
            let newName = try next.freshAlbumName(newName, replacing: name)
            next.albums = next.albums.map { $0 == name ? newName : $0 }
            next.placements = next.placements.mapValues { names in
                LibrarySnapshot.ordered(names.map { $0 == name ? newName : $0 })
            }
        case let .deleteAlbum(name):
            next.albums.removeAll { $0 == name }
            next.placements = next.placements.compactMapValues { names in
                let rest = names.filter { $0 != name }
                return rest.isEmpty ? nil : rest
            }
        case let .addToAlbum(name, itemIDs):
            for itemID in itemIDs { next.place(itemID, in: [name]) }
        case let .removeFromAlbum(name, itemID):
            let rest = next.albums(of: itemID).filter { $0 != name }
            next.placements[itemID] = rest.isEmpty ? nil : rest
        case let .mark(mark, target):
            next.annotations = next.annotations.marking(mark, at: target, date: date)
        case let .unmark(mark, target):
            next.annotations = next.annotations.unmarking(mark, at: target, date: date)
        case let .note(text, target):
            next.annotations = next.annotations.noting(text, at: target, date: date)
        case let .removeAnnotation(id):
            next.annotations.removeAll { $0.id == id }
        case let .removeVideoFile(itemID):
            next.videoFiles[itemID] = nil
        case let .delete(itemID):
            next.packages.removeAll { $0.material.id == itemID }
            next.books.removeAll { $0.id == itemID }
            next.forgetMarks(of: itemID)
            next.placements[itemID] = nil
            next.archived.removeAll { $0 == itemID }
            next.addedAt[itemID] = nil
            next.articleRevisions[itemID] = nil
            next.videoFiles[itemID] = nil
            if let catalog = next.browserCatalog, itemID.hasPrefix("link:") {
                next.browserCatalog = catalog.removing(url: String(itemID.dropFirst(5)))
            }
        }
        return next
    }

    private func freshAlbumName(_ name: String, replacing current: String? = nil) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LibraryError.emptyAlbumName }
        guard name == current || !albums.contains(name) else { throw LibraryError.albumNameTaken(name) }
        return name
    }
}
