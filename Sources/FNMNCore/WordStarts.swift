import Foundation

/// The opening letters of each word, set bold so the eye lands on the start of a word and the rest is guessed
/// (the style sold as Bionic Reading).
public enum WordStarts {
    /// The ranges, in characters of `text`, to set bold: the first letters of every word. A word is a run of letters
    /// and digits, with an apostrophe or hyphen inside it; a word of one to three letters gets one bold letter, a
    /// longer one a little under half.
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

    /// How many opening letters of a word this long are bold.
    public static func boldLength(of length: Int) -> Int {
        length <= 3 ? min(length, 1) : Int((Double(length) * 0.45).rounded())
    }
}
