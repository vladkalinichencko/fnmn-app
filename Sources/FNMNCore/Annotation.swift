import CryptoKit
import Foundation

public enum TextMark: String, Codable, CaseIterable, Sendable {
    case highlight, strikethrough
}

/// A run of a paragraph that carries a mark. The quote anchors it: character offsets move whenever the renderer
/// changes, the paragraph text does not.
public struct QuoteMark: Codable, Hashable, Sendable {
    public var quote: String
    public var mark: TextMark

    public init(quote: String, mark: TextMark) {
        self.quote = quote
        self.mark = mark
    }
}

/// Everything the reader keeps on one paragraph: its marked runs and its note. A paragraph has one record, so a
/// second highlight joins the first and the note sits beside both.
public struct Annotation: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var materialID: String
    public var piece: Int
    /// The paragraph's plain text when the record was last written, so the shelf shows it without opening the material.
    public var text: String
    public var marks: [QuoteMark]
    public var note: String
    public var updatedAt: Date?

    public init(
        id: UUID? = nil, materialID: String, piece: Int, text: String,
        marks: [QuoteMark] = [], note: String = "", updatedAt: Date? = nil
    ) {
        self.id = id ?? Self.id(materialID: materialID, piece: piece)
        self.materialID = materialID
        self.piece = piece
        self.text = text
        self.marks = marks
        self.note = note
        self.updatedAt = updatedAt
    }

    /// The same on every device, so a deletion made on one finds the record on the others.
    static func id(materialID: String, piece: Int) -> UUID {
        let digest = Array(SHA256.hash(data: Data("\(materialID)#\(piece)".utf8)).prefix(16))
        return digest.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
    }

    /// What the card shows of the paragraph: the marked runs, or the whole paragraph when none is marked.
    public var quoted: String {
        marks.isEmpty ? text : marks.map(\.quote).joined(separator: "\n")
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

    func span(of quote: String) -> TextSpan? {
        let found = (text as NSString).range(of: quote)
        return found.location == NSNotFound ? nil : TextSpan(start: found.location, length: found.length)
    }

    func holds(_ annotation: Annotation) -> Bool {
        annotation.materialID == materialID && annotation.piece == piece
    }

    func touchesMark(_ mark: TextMark, in annotation: Annotation) -> Bool {
        holds(annotation) && annotation.marks.contains {
            $0.mark == mark && span(of: $0.quote)?.touches(resolvedSpan) == true
        }
    }
}

/// What the selection menu offers for a target: each mark or its removal, plus the note.
public enum AnnotationCommand: Equatable, Sendable {
    case mark(TextMark)
    case unmark(TextMark)
}

public func annotationCommands(_ annotations: [Annotation], at target: AnnotationTarget) -> [AnnotationCommand] {
    TextMark.allCases.map { mark in
        annotations.contains { target.touchesMark(mark, in: $0) } ? .unmark(mark) : .mark(mark)
    }
}

extension Array where Element == Annotation {
    /// Marks the target and folds every touching run with the same mark into one.
    func marking(_ mark: TextMark, at target: AnnotationTarget, date: Date) -> [Annotation] {
        editing(target, date: date) { record in
            var merged = target.resolvedSpan
            record.marks.removeAll { existing in
                guard existing.mark == mark, let span = target.span(of: existing.quote), span.touches(merged) else { return false }
                merged = merged.union(span)
                return true
            }
            record.marks.append(QuoteMark(quote: target.quote(merged), mark: mark))
        }
    }

    /// Removes the mark from every run it touches; a paragraph that keeps its note stays as a note.
    func unmarking(_ mark: TextMark, at target: AnnotationTarget, date: Date) -> [Annotation] {
        guard contains(where: { target.touchesMark(mark, in: $0) }) else { return self }
        return editing(target, date: date) { record in
            record.marks.removeAll { $0.mark == mark && target.span(of: $0.quote)?.touches(target.resolvedSpan) == true }
        }
    }

    /// Writes the paragraph's note.
    func noting(_ note: String, at target: AnnotationTarget, date: Date) -> [Annotation] {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return editing(target, date: date) { $0.note = text }
    }

    /// Changes the paragraph's record, making it when the paragraph has none, and drops it once it holds neither a
    /// mark nor a note.
    private func editing(_ target: AnnotationTarget, date: Date, _ change: (inout Annotation) -> Void) -> [Annotation] {
        var next = self
        let index = next.firstIndex { target.holds($0) }
        var record = index.map { next[$0] } ?? Annotation(materialID: target.materialID, piece: target.piece, text: target.text)
        change(&record)
        record.text = target.text
        record.updatedAt = date
        let keeps = !record.marks.isEmpty || !record.note.isEmpty
        switch (index, keeps) {
        case let (index?, true): next[index] = record
        case let (index?, false): next.remove(at: index)
        case (nil, true): next.append(record)
        case (nil, false): break
        }
        return next
    }
}

/// The part of a paragraph a card shows: all of it when it is short, otherwise a window that opens just before the
/// first mark, cut between words, with an ellipsis where text was left out.
public struct AnnotationExcerpt: Equatable, Sendable {
    public struct Run: Equatable, Sendable {
        public var range: NSRange
        public var mark: TextMark
    }

    public var text: String
    /// The marked runs inside `text`, in UTF-16 offsets.
    public var runs: [Run]
}

extension Annotation {
    public func excerpt(limit: Int = 260) -> AnnotationExcerpt {
        let paragraph = text.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        let runs = marks.compactMap { mark -> AnnotationExcerpt.Run? in
            let found = paragraph.range(of: mark.quote)
            return found.location == NSNotFound ? nil : AnnotationExcerpt.Run(range: found, mark: mark.mark)
        }
        guard paragraph.length > limit else { return AnnotationExcerpt(text: paragraph as String, runs: runs) }

        var start = max((runs.map(\.range.location).min() ?? 0) - 40, 0)
        if start > 0 {
            let before = paragraph.range(of: " ", options: .backwards, range: NSRange(location: 0, length: start))
            start = before.location == NSNotFound ? 0 : before.location + 1
        }
        var end = min(start + limit, paragraph.length)
        if end < paragraph.length {
            let space = paragraph.range(of: " ", options: .backwards, range: NSRange(location: start, length: end - start))
            end = space.location == NSNotFound ? paragraph.rangeOfComposedCharacterSequence(at: end).location : space.location
        }
        let lead = start > 0 ? "…" : "", tail = end < paragraph.length ? "…" : ""
        let window = NSRange(location: start, length: end - start)
        let shifted = runs.compactMap { run -> AnnotationExcerpt.Run? in
            let inside = NSIntersectionRange(run.range, window)
            guard inside.length > 0 else { return nil }
            return AnnotationExcerpt.Run(range: NSRange(location: inside.location - start + lead.utf16.count, length: inside.length), mark: run.mark)
        }
        return AnnotationExcerpt(text: lead + paragraph.substring(with: window) + tail, runs: shifted)
    }
}
