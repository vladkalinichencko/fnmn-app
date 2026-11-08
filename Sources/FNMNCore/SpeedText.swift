import Foundation

/// How long the reader waits after a word, by what ends it.
public enum SpeedPause: Int, Comparable, Sendable {
    case none, comma, sentence, paragraph

    public static func < (lhs: SpeedPause, rhs: SpeedPause) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One step of speed reading: a word of a paragraph, or a block that cannot be read a word at a time (a formula, code,
/// a table, a picture, a video) and is shown whole.
public struct SpeedToken: Equatable, Sendable {
    public let block: Int
    /// The word as it stands in the text, with the punctuation around it; empty for a block shown whole.
    public let text: String
    /// How much of its block is read once this token has been shown: the share of the block's tokens up to it.
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

    /// The beats the token stays on screen beyond the one every word gets: a long word, a number and the pause after
    /// it. A setting of pauses scales them, from none to all.
    public var extraBeats: Double {
        guard !isStop else { return 0 }
        let letters = text.filter { $0.isLetter || $0.isNumber }.count
        let long = min(Double(max(letters - 7, 0)) * 0.08, 0.6)
        let number = text.contains(where: \.isNumber) ? 0.3 : 0
        let pause: Double = switch pause {
        case .none: 0
        case .comma: 0.75
        case .sentence: 1.5
        case .paragraph: 2.5
        }
        return long + number + pause
    }
}

/// A document's text from a place on, as speed reading shows it: words one or two at a time, blocks of anything but
/// prose as stops. Built once when the mode opens, off the main thread, since a book holds hundreds of thousands of
/// words.
public struct SpeedText: Sendable {
    public let tokens: [SpeedToken]
    /// The words and the extra beats from each token to the end, so the time left is known at once on every word.
    private let wordsAfter: [Double]
    private let extraAfter: [Double]

    /// The text of every plate from `start` on, without what the reading line has already passed in its block.
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
        var extra = [Double](repeating: 0, count: tokens.count + 1)
        for index in tokens.indices.reversed() {
            words[index] = words[index + 1] + (tokens[index].isStop ? 0 : 1)
            extra[index] = extra[index + 1] + tokens[index].extraBeats
        }
        wordsAfter = words
        extraAfter = extra
    }

    /// The tokens shown together from `index`: up to `words` words of one sentence, ending early at a pause, or a stop
    /// alone.
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

    /// How long a frame stays on screen, in seconds. Every word gets a beat of the chosen speed, and `pauses`, from 0
    /// to 1, adds the extra beats of long words, numbers and punctuation.
    public func duration(of frame: Range<Int>, wordsPerMinute: Int, pauses: Double) -> Double {
        let beats = tokens[frame].reduce(0) { $0 + 1 + pauses * $1.extraBeats }
        return beats * 60 / Double(max(wordsPerMinute, 1))
    }

    /// Minutes to read from `index` to the end at this speed; the blocks shown whole are not counted.
    public func minutesLeft(from index: Int, wordsPerMinute: Int, pauses: Double) -> Double {
        let index = min(max(index, 0), tokens.count)
        return (wordsAfter[index] + pauses * extraAfter[index]) / Double(max(wordsPerMinute, 1))
    }

    /// Where going back a sentence lands from a frame starting at `index`: the start of the sentence it stands in, or,
    /// from a sentence's first word, the start of the one before. A block shown whole counts as a sentence.
    public func sentenceStart(before index: Int) -> Int {
        tokens.indices.prefix(min(max(index, 0), tokens.count)).last { tokens[$0].startsSentence || tokens[$0].isStop } ?? 0
    }

    /// The start of the next sentence after the frame at `index`, nil at the last one.
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

    /// The letter the eye is meant to rest on, as an offset into `text`: a little left of the middle, the way a word
    /// is recognized fastest (the optimal recognition point). Leading quotes and brackets are passed over.
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

    /// A block's tokens. Prose becomes words; a part that holds code, a formula, a table or a picture becomes one stop
    /// in its place, and parts like that standing together one stop. A picture, a video or a live page is a stop.
    public static func tokens(in block: DocumentBlock, at index: Int) -> [SpeedToken] {
        let parts: [[String]?] = switch block {
        case .heading: []
        case .image, .video, .interactive: [nil]
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

    /// The parts of a block's Markdown between blank lines, keeping a code fence or a `$$` formula whole.
    static func segments(of markdown: String) -> [String] {
        MarkdownParts.split(markdown)
    }

    /// Whether a part of a paragraph cannot be read a word at a time: code, a formula, a table or a picture.
    /// A dollar amount such as `$5 and $10` is prose.
    static func isRich(_ segment: String) -> Bool {
        let trimmed = segment.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { return true }
        if ["$$", "\\[", "\\(", "![", "<img", "<table", "<iframe", "<video"].contains(where: segment.contains) { return true }
        if segment.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }) { return true }
        return segment.replacing("\\$", with: "").matches(of: /\$([^$\n]+?)\$/).contains { match in
            !InlineMath.looksLikeProse(String(match.1))
        }
    }

    /// The text of a part of prose as it reads, one string for each paragraph, list item or quote in it: links show
    /// their text, emphasis and code markers go, `==marks==` lose their signs.
    static func paragraphs(of segment: String) -> [String] {
        let cleaned = segment
            .replacing(/<[^>\n]+>/, with: " ")
            .replacing("==", with: "")
        // Most paragraphs have no Markdown in them, and parsing is what takes the time in a book.
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

    /// A paragraph's words with the pause after each. A dash standing alone is a pause after the word before it; a
    /// full stop ends a sentence only before a capital, a digit or the paragraph's end, so "e.g. this" reads on.
    static func words(of paragraph: String) -> [(text: String, pause: SpeedPause)] {
        var words: [(text: String, pause: SpeedPause)] = []
        for piece in paragraph.split(whereSeparator: \.isWhitespace).map(String.init) {
            guard piece.contains(where: { $0.isLetter || $0.isNumber }) else {
                if let last = words.indices.last, piece.contains(where: { "—–-:;".contains($0) }) {
                    words[last].pause = max(words[last].pause, .comma)
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
        guard let last = ending.last else { return .none }
        if ".!?…".contains(last) { return .sentence }
        if ",;:—–".contains(last) { return .comma }
        return .none
    }
}
