import Foundation

public enum WordStarts {
    public static func ranges(in text: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var offset = 0
        var wordStart: Int?
        var characters = Array(text)
        characters.append(" ")
        for (index, character) in characters.enumerated() {
            let inWord = character.isLetter || character.isNumber
                || (wordStart != nil && "'’-".contains(character) && index + 1 < characters.count && characters[index + 1].isLetter)
            if inWord, wordStart == nil {
                wordStart = offset
            } else if !inWord, let start = wordStart {
                let length = offset - start
                ranges.append(start..<start + boldLength(of: length))
                wordStart = nil
            }
            offset += 1
        }
        return ranges
    }

    public static func boldLength(of length: Int) -> Int {
        length <= 3 ? min(length, 1) : Int((Double(length) * 0.45).rounded())
    }
}
