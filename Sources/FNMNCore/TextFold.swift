import Foundation

/// The one way a query and the text it is matched against are folded: case, diacritics and width. The library
/// folds its search text once and the magazine folds a post as it is searched, but both answer alike.
public enum TextFold {
    public static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
