import Foundation

public enum SpeedPause: Int, Comparable, Sendable {
    case none, comma, clause, sentence, paragraph

    public static func < (lhs: SpeedPause, rhs: SpeedPause) -> Bool { lhs.rawValue < rhs.rawValue }

    var kind: SpeedPauseKind? {
        switch self {
        case .none: nil
        case .comma: .comma
        case .clause: .clause
        case .sentence: .sentence
        case .paragraph: .paragraph
        }
    }

    var beats: Double {
        switch self {
        case .none: 0
        case .comma: 0.75
        case .clause: 1.1
        case .sentence: 1.5
        case .paragraph: 2.5
        }
    }
}

public struct SpeedToken: Equatable, Sendable {
    public let block: Int
    public let text: String
    public let share: Double
    public let pause: SpeedPause
    public let startsSentence: Bool

    public var isStop: Bool { text.isEmpty }

    public init(block: Int, text: String, share: Double, pause: SpeedPause, startsSentence: Bool) {
        self.block = block
        self.text = text
        self.share = share
        self.pause = pause
        self.startsSentence = startsSentence
    }

    public func extraBeats(_ profile: SpeedPauseProfile) -> Double {
        guard !isStop else {
            return 0
        }
        let letters = text.filter { $0.isLetter || $0.isNumber }.count
        let long = min(Double(max(letters - 7, 0)) * 0.08, 0.6) * profile.share(.longWords)
        let number = (text.contains(where: \.isNumber) ? 0.3 : 0) * profile.share(.numbers)
        let pausing = pause.kind.map { pause.beats * profile.share($0) } ?? 0
        return long + number + pausing
    }
}

public struct SpeedText: Sendable {
    public let tokens: [SpeedToken]
    private let wordsAfter: [Double]

    public init(document: ReaderDocument, from start: ReadingLine) {
        var tokens: [SpeedToken] = []
        for block in document.plates where block >= start.piece {
            let own = Self.tokens(in: document.blocks[block], at: block)
            tokens += block == start.piece ? own.filter { $0.share > start.fraction } : own
        }
        self.init(tokens: tokens)
    }

    public init(tokens: [SpeedToken]) {
        self.tokens = tokens
        var words = [Double](repeating: 0, count: tokens.count + 1)
        for index in tokens.indices.reversed() {
            words[index] = words[index + 1] + (tokens[index].isStop ? 0 : 1)
        }
        wordsAfter = words
    }

    public func frame(at index: Int, words: Int) -> Range<Int> {
        guard tokens.indices.contains(index) else { return index..<index }
        guard !tokens[index].isStop else { return index..<index + 1 }
        var end = index + 1
        while end - index < words, end < tokens.count, tokens[end - 1].pause == .none,
              !tokens[end].isStop, !tokens[end].startsSentence, tokens[end].block == tokens[index].block {
            end += 1
        }
        return index..<end
    }

    public func duration(of frame: Range<Int>, wordsPerMinute: Int, pauses: SpeedPauseProfile) -> Double {
        let beats = tokens[frame].reduce(0) { $0 + 1 + $1.extraBeats(pauses) }
        return beats * 60 / Double(max(wordsPerMinute, 1))
    }

    public func minutesLeft(from index: Int, wordsPerMinute: Int, pauses: SpeedPauseProfile) -> Double {
        let index = min(max(index, 0), tokens.count)
        let extra = tokens[index...].reduce(0.0) { $0 + $1.extraBeats(pauses) }
        return (wordsAfter[index] + extra) / Double(max(wordsPerMinute, 1))
    }

    public func sentenceStart(before index: Int) -> Int {
        tokens.indices.prefix(min(max(index, 0), tokens.count)).last { tokens[$0].startsSentence || tokens[$0].isStop } ?? 0
    }

    public func sentenceStart(after index: Int) -> Int? {
        tokens.indices.dropFirst(index + 1).first { tokens[$0].startsSentence || tokens[$0].isStop }
    }

    public func endedBlock(at frame: Range<Int>) -> Int? {
        guard !frame.isEmpty, frame.upperBound < tokens.count else {
            return nil
        }
        let last = tokens[frame.upperBound - 1]
        guard !last.isStop, tokens[frame.upperBound].block != last.block else {
            return nil
        }
        return last.block
    }

    public static func pivot(of text: String) -> Int {
        let characters = Array(text)
        let lead = characters.firstIndex { $0.isLetter || $0.isNumber } ?? 0
        let letters = characters[lead...].prefix { !$0.isWhitespace }.filter { $0.isLetter || $0.isNumber }.count
        let offset = switch letters {
        case ...1: 0
        case 2...5: 1
        case 6...9: 2
        case 10...13: 3
        default: 4
        }
        return min(lead + offset, max(characters.count - 1, 0))
    }

    public static func tokens(in block: DocumentBlock, at index: Int) -> [SpeedToken] {
        let parts: [[String]?] = switch block {
        case .heading, .interactive: []
        case .image, .video: [nil]
        case let .text(markdown):
            segments(of: markdown).map { isRich($0) ? nil : paragraphs(of: $0) }
        }
        var items: [(text: String, pause: SpeedPause)?] = []
        for part in parts {
            guard let part else {
                if items.last.map({ $0 != nil }) ?? true { items.append(nil) }
                continue
            }
            for paragraph in part {
                items += words(of: paragraph).map(Optional.some)
            }
        }
        var tokens: [SpeedToken] = []
        var startsSentence = true
        for (position, item) in items.enumerated() {
            let share = Double(position + 1) / Double(items.count)
            guard let item else {
                tokens.append(SpeedToken(block: index, text: "", share: share, pause: .paragraph, startsSentence: true))
                startsSentence = true
                continue
            }
            tokens.append(SpeedToken(block: index, text: item.text, share: share, pause: item.pause, startsSentence: startsSentence))
            startsSentence = item.pause >= .sentence
        }
        return tokens
    }

    static func segments(of markdown: String) -> [String] {
        MarkdownParts.split(markdown)
    }

    static func isRich(_ segment: String) -> Bool {
        let trimmed = segment.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { return true }
        if ["$$", "\\[", "\\(", "![", "<img", "<table", "<iframe", "<video"].contains(where: segment.contains) { return true }
        if segment.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }) { return true }
        return segment.replacing("\\$", with: "").matches(of: /\$([^$\n]+?)\$/).contains { match in
            !InlineMath.looksLikeProse(String(match.1))
        }
    }

    static func paragraphs(of segment: String) -> [String] {
        let cleaned = segment
            .replacing(/<[^>\n]+>/, with: " ")
            .replacing("==", with: "")
        let marked = cleaned.contains { "*_[`\\&".contains($0) }
            || cleaned.split(separator: "\n").contains { $0.first.map { "-+>#".contains($0) || $0.isNumber } ?? false }
        guard marked else { return [cleaned] }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let text = try? AttributedString(markdown: cleaned, options: options) else { return [cleaned] }
        var paragraphs: [String] = []
        var identity: Int?
        for run in text.runs {
            let piece = String(text[run.range].characters)
            let own = run.presentationIntent?.components.first?.identity
            if own != identity || paragraphs.isEmpty {
                paragraphs.append(piece)
                identity = own
            } else {
                paragraphs[paragraphs.count - 1] += piece
            }
        }
        return paragraphs
    }

    static func words(of paragraph: String) -> [(text: String, pause: SpeedPause)] {
        var words: [(text: String, pause: SpeedPause)] = []
        for piece in paragraph.split(whereSeparator: \.isWhitespace).map(String.init) {
            guard piece.contains(where: { $0.isLetter || $0.isNumber }) else {
                if let last = words.indices.last, piece.contains(where: { "—–-:;".contains($0) }) {
                    words[last].pause = max(words[last].pause, .clause)
                }
                continue
            }
            words.append((piece, pause(after: piece)))
        }
        for index in words.indices.dropLast() where words[index].pause == .sentence {
            let next = words[index + 1].text.first { $0.isLetter || $0.isNumber }
            let ending = words[index].text.trimmingCharacters(in: Self.closing)
            if ending.hasSuffix("."), !ending.hasSuffix("..."), let next, next.isLowercase {
                words[index].pause = .none
            }
        }
        if let last = words.indices.last { words[last].pause = .paragraph }
        return words
    }

    private static let closing = CharacterSet(charactersIn: "\"'”’»)]*_")

    private static func pause(after word: String) -> SpeedPause {
        let ending = word.trimmingCharacters(in: closing)
        guard let last = ending.last else {
            return .none
        }
        if ".!?…".contains(last) {
            return .sentence
        }
        if "—–:;".contains(last) {
            return .clause
        }
        if ",".contains(last) {
            return .comma
        }
        return .none
    }
}
