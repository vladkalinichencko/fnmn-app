import Foundation

struct LegacyAnnotation: Decodable {
    var id: UUID
    var materialID: String
    var piece: Int
    var quote: String
    var note: String
    var mark: TextMark?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, materialID, piece, quote, note, mark, updatedAt
        case caption
    }

    init(from decoder: Decoder) throws {
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
}

struct StoredAnnotations: Decodable {
    let records: [Annotation]

    init(from decoder: Decoder) throws {
        if let current = try? [Annotation](from: decoder) {
            records = current
        } else {
            records = Self.merging(try [LegacyAnnotation](from: decoder))
        }
    }

    static func merging(_ legacy: [LegacyAnnotation]) -> [Annotation] {
        var order: [String] = []
        var paragraphs: [String: [LegacyAnnotation]] = [:]
        for record in legacy {
            let key = "\(record.materialID)#\(record.piece)"
            if paragraphs[key] == nil { order.append(key) }
            paragraphs[key, default: []].append(record)
        }
        return order.compactMap { key in
            let records = paragraphs[key] ?? []
            let marks = records.compactMap { record -> QuoteMark? in
                guard let mark = record.mark, !record.quote.isEmpty else { return nil }
                return QuoteMark(quote: record.quote, mark: mark)
            }.reduce(into: [QuoteMark]()) { unique, mark in
                if !unique.contains(mark) { unique.append(mark) }
            }
            let note = records.map(\.note).filter { !$0.isEmpty }.joined(separator: "\n")
            guard !marks.isEmpty || !note.isEmpty else { return nil }
            var text = records.map(\.quote).max { $0.count < $1.count } ?? ""
            for mark in marks where !text.contains(mark.quote) {
                text += (text.isEmpty ? "" : " … ") + mark.quote
            }
            return Annotation(
                materialID: records[0].materialID, piece: records[0].piece, text: text, marks: marks, note: note,
                updatedAt: records.compactMap(\.updatedAt).max()
            )
        }
    }
}
