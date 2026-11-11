import Foundation

public struct ReaderDocument: Equatable, Sendable {
    public let blocks: [DocumentBlock]
    public let repeatedTitle: Int?
    public let lead: Int?
    public let sections: [Int: HeadingSection]
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

    public func heading(before index: Int) -> (index: Int, title: String)? {
        for candidate in blocks.indices.prefix(min(max(index, 0), blocks.count)).reversed() {
            if case let .heading(_, title) = blocks[candidate] { return (candidate, title) }
        }
        return nil
    }

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
    public let size: Int
    public let end: Int
}
