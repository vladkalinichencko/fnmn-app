import Foundation

/// An open document as the reader shows it, worked out once when it opens and off the main thread.
public struct ReaderDocument: Equatable, Sendable {
    public let blocks: [DocumentBlock]
    /// The document's own first heading when it repeats the title already shown in the header.
    public let repeatedTitle: Int?
    /// A picture that opens the text before any paragraph: the article's cover, shown as the header.
    public let lead: Int?
    /// What each heading holds: its block count, shown when the document is folded, and where it ends.
    public let sections: [Int: HeadingSection]
    /// The blocks read one at a time, in order: every block but the headings and the cover.
    public let plates: [Int]

    public init(markdown: String, title: String) {
        let blocks = ArticleBody.blocks(in: markdown)
        self.blocks = blocks
        repeatedTitle = blocks.firstIndex { block in
            if case let .heading(_, heading) = block { heading == title } else { false }
        }
        let lead = blocks.firstIndex { if case .heading = $0 { false } else { true } }.flatMap { index in
            if case .image = blocks[index] { index } else { nil }
        }
        self.lead = lead
        sections = Self.sections(blocks)
        plates = blocks.indices.filter { index in
            if case .heading = blocks[index] { false } else { index != lead }
        }
    }

    /// The heading of the innermost section a block lies in: the nearest heading before it, of whatever level, since a
    /// section ends only at a heading.
    public func heading(before index: Int) -> (index: Int, title: String)? {
        for candidate in blocks.indices.prefix(min(max(index, 0), blocks.count)).reversed() {
            if case let .heading(_, title) = blocks[candidate] { return (candidate, title) }
        }
        return nil
    }

    /// For each heading, the blocks that follow it until a heading of the same or a higher level.
    private static func sections(_ blocks: [DocumentBlock]) -> [Int: HeadingSection] {
        var sections: [Int: HeadingSection] = [:]
        for (index, block) in blocks.enumerated() {
            guard case let .heading(level, _) = block else { continue }
            let rest = blocks[(index + 1)...]
            let end = rest.firstIndex { if case let .heading(other, _) = $0 { other <= level } else { false } } ?? blocks.endIndex
            let size = blocks[(index + 1)..<end].filter { if case .heading = $0 { false } else { true } }.count
            sections[index] = HeadingSection(size: size, end: end)
        }
        return sections
    }
}

public struct HeadingSection: Equatable, Sendable {
    /// Blocks under the heading that are not headings themselves.
    public let size: Int
    /// The index of the next heading of the same or a higher level, or the end of the document.
    public let end: Int
}
