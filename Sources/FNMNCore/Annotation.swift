import Foundation

public enum TextMark: String, Codable, CaseIterable, Sendable {
    case highlight, strikethrough
}

/// A highlight, a strikethrough or a margin note inside one paragraph.
/// The quote anchors it: character offsets move whenever the renderer changes, the paragraph text does not.
/// An empty quote belongs to the whole paragraph.
public struct Annotation: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var materialID: String
    public var piece: Int
    public var quote: String
    public var note: String
    public var mark: TextMark?
    public var updatedAt: Date?

    public init(id: UUID = UUID(), materialID: String, piece: Int, quote: String, note: String = "", mark: TextMark? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.materialID = materialID
        self.piece = piece
        self.quote = quote
        self.note = note
        self.mark = mark
        self.updatedAt = updatedAt
    }
}

/// A run of a paragraph's text in UTF-16 offsets, the unit UIKit selection reports.
public struct TextSpan: Codable, Equatable, Hashable, Sendable {
    public var start: Int
    public var length: Int

    public init(start: Int, length: Int) {
        self.start = start
        self.length = length
    }

    var end: Int { start + length }

    func touches(_ other: TextSpan) -> Bool {
        start <= other.end && other.start <= end
    }

    func union(_ other: TextSpan) -> TextSpan {
        let lower = min(start, other.start)
        return TextSpan(start: lower, length: max(end, other.end) - lower)
    }
}

/// The paragraph an edit applies to, as the reader shows it. A nil span is the whole paragraph.
public struct AnnotationTarget: Codable, Equatable, Sendable {
    public let materialID: String
    public let piece: Int
    public let text: String
    public let span: TextSpan?

    public init(materialID: String, piece: Int, text: String, span: TextSpan? = nil) {
        self.materialID = materialID
        self.piece = piece
        self.text = text
        self.span = span
    }

    var resolvedSpan: TextSpan { span ?? TextSpan(start: 0, length: (text as NSString).length) }

    func quote(_ span: TextSpan) -> String {
        (text as NSString).substring(with: NSRange(location: span.start, length: span.length))
    }

    func span(of annotation: Annotation) -> TextSpan? {
        guard annotation.materialID == materialID, annotation.piece == piece else { return nil }
        guard !annotation.quote.isEmpty else { return TextSpan(start: 0, length: (text as NSString).length) }
        let found = (text as NSString).range(of: annotation.quote)
        guard found.location != NSNotFound else { return nil }
        return TextSpan(start: found.location, length: found.length)
    }
}

/// What the selection menu offers for a target: each mark or its removal, plus the note.
public enum AnnotationCommand: Equatable, Sendable {
    case mark(TextMark)
    case unmark(TextMark)
}

public func annotationCommands(_ annotations: [Annotation], at target: AnnotationTarget) -> [AnnotationCommand] {
    TextMark.allCases.map { mark in
        annotations.contains { $0.mark == mark && target.span(of: $0)?.touches(target.resolvedSpan) == true }
            ? .unmark(mark) : .mark(mark)
    }
}

extension Array where Element == Annotation {
    /// Marks the target and folds every touching annotation with the same mark into one record.
    func marking(_ mark: TextMark, at target: AnnotationTarget, date: Date) -> [Annotation] {
        var merged = target.resolvedSpan
        var kept: [Annotation] = []
        var folded: [Annotation] = []
        for annotation in self {
            if annotation.mark == mark, let span = target.span(of: annotation), span.touches(merged) {
                merged = merged.union(span)
                folded.append(annotation)
            } else {
                kept.append(annotation)
            }
        }
        let notes = folded.map(\.note).filter { !$0.isEmpty }
        kept.append(Annotation(
            id: folded.first?.id ?? UUID(),
            materialID: target.materialID,
            piece: target.piece,
            quote: target.quote(merged),
            note: notes.joined(separator: "\n"),
            mark: mark,
            updatedAt: date
        ))
        return kept
    }

    /// Removes the mark from every annotation it touches; a record that still carries a note stays as a note.
    func unmarking(_ mark: TextMark, at target: AnnotationTarget, date: Date) -> [Annotation] {
        compactMap { annotation in
            guard annotation.mark == mark, target.span(of: annotation)?.touches(target.resolvedSpan) == true else { return annotation }
            guard !annotation.note.isEmpty else { return nil }
            var note = annotation
            note.mark = nil
            note.updatedAt = date
            return note
        }
    }

    /// Writes the note of the target's own record; an empty note on an unmarked record removes it.
    func noting(_ note: String, at target: AnnotationTarget, date: Date) -> [Annotation] {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let quote = target.span.map(target.quote) ?? ""
        var next = self
        if let index = next.firstIndex(where: { $0.materialID == target.materialID && $0.piece == target.piece && $0.quote == quote }) {
            next[index].note = text
            next[index].updatedAt = date
            if text.isEmpty && next[index].mark == nil { next.remove(at: index) }
        } else if !text.isEmpty {
            next.append(Annotation(materialID: target.materialID, piece: target.piece, quote: quote, note: text, updatedAt: date))
        }
        return next
    }
}

extension Annotation: Codable {
    enum CodingKeys: String, CodingKey {
        case id, materialID, piece, quote, note, mark, updatedAt
        case caption
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        materialID = try container.decode(String.self, forKey: .materialID)
        piece = try container.decode(Int.self, forKey: .piece)
        quote = try container.decode(String.self, forKey: .quote)
        note = try container.decodeIfPresent(String.self, forKey: .note)
            ?? container.decodeIfPresent(String.self, forKey: .caption) ?? ""
        if container.contains(.mark) {
            mark = try container.decodeIfPresent(TextMark.self, forKey: .mark)
        } else {
            mark = quote.isEmpty ? nil : .highlight
        }
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(materialID, forKey: .materialID)
        try container.encode(piece, forKey: .piece)
        try container.encode(quote, forKey: .quote)
        try container.encode(note, forKey: .note)
        try container.encode(mark, forKey: .mark)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}
