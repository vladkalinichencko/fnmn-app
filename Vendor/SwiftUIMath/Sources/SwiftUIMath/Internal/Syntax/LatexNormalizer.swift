import Foundation

extension Math.Parser {
  /// Papers write TeX for a full amsmath; the parser reads a smaller language. Commands and environments it lacks
  /// are rewritten into the ones it has, or dropped when they only mark the source (`\label`, `\phantom`).
  static func normalized(_ latex: String) -> String {
    guard latex.contains("\\") else { return latex }
    let source = latex
      .replacing(/\\(begin|end)\{(?:align|flalign)\*?\}/) { "\\\($0.output.1){aligned}" }
      .replacing(/\\(begin|end)\{(?:gather|eqnarray)\*\}/) { "\\\($0.output.1){\($0.output.0.contains("gather") ? "gather" : "eqnarray")}" }
      .replacing(/\\(?:begin|end)\{(?:equation|multline)\*?\}/, with: "")
    var output = ""
    var rest = Substring(source)
    while let slash = rest.firstIndex(of: "\\") {
      output += rest[..<slash]
      rest = rest[rest.index(after: slash)...]
      let name = String(rest.prefix { $0.isLetter })
      guard !name.isEmpty else {
        // `\\`, `\,`, `\{`: a symbol command stays as it is, with the character it escapes.
        output += "\\"
        if let symbol = rest.first {
          output.append(symbol)
          rest = rest.dropFirst()
        }
        continue
      }
      rest = rest.dropFirst(name.count)
      output += rewrite(command: name, rest: &rest)
    }
    return output + rest
  }

  private static let renamed: [String: String] = [
    "boldsymbol": "\\mathbf", "bold": "\\mathbf", "dots": "\\ldots", "dotsb": "\\cdots", "dotsc": "\\ldots",
    "intercal": "\\top", "gt": ">", "lt": "<", "lvert": "\\vert", "rvert": "\\vert", "lVert": "\\Vert",
    "rVert": "\\Vert", "newline": "\\\\", "bmod": "\\;\\mathrm{mod}\\;", "argmax": "\\mathrm{argmax}",
    "argmin": "\\mathrm{argmin}", "blacksquare": "\u{25A0}",
  ]

  /// Commands whose braced argument goes and leaves a space, or nothing.
  private static let spaced: [String: String] = ["phantom": "\\;", "hphantom": "\\;", "hspace": "\\quad", "vphantom": ""]
  private static let dropped: Set<String> = ["label", "nonumber", "notag"]

  private static func rewrite(command: String, rest: inout Substring) -> String {
    if let name = renamed[command] {
      // A command name ends at a non-letter; the replacement must not run into the letters after it.
      return name.last?.isLetter == true && rest.first?.isLetter == true ? name + " " : name
    }
    if let space = spaced[command] {
      _ = braced(&rest)
      return space
    }
    if dropped.contains(command) {
      _ = braced(&rest)
      return ""
    }
    if command == "boxed", let inside = braced(&rest) {
      return "{" + normalized(inside) + "}"
    }
    if command == "xrightarrow" || command == "xleftarrow" {
      let below = bracketed(&rest)
      guard let above = braced(&rest) else { return command == "xrightarrow" ? "\\rightarrow" : "\\leftarrow" }
      let arrow = command == "xrightarrow" ? "\\rightarrow" : "\\leftarrow"
      let underset = below.map { "\\underset{\(normalized($0))}{\(arrow)}" } ?? arrow
      return "\\overset{\(normalized(above))}{\(underset)}"
    }
    return "\\" + command
  }

  /// Takes a `{…}` argument off the front of `rest`, skipping blanks before it and a star after a command name.
  private static func braced(_ rest: inout Substring) -> String? {
    var probe = rest
    if probe.first == "*" { probe = probe.dropFirst() }
    probe = probe.drop { $0 == " " }
    guard probe.first == "{" else { return nil }
    var depth = 0
    var index = probe.startIndex
    while index < probe.endIndex {
      switch probe[index] {
      case "{": depth += 1
      case "}":
        depth -= 1
        if depth == 0 {
          let inside = String(probe[probe.index(after: probe.startIndex)..<index])
          rest = probe[probe.index(after: index)...]
          return inside
        }
      default: break
      }
      index = probe.index(after: index)
    }
    return nil
  }

  private static func bracketed(_ rest: inout Substring) -> String? {
    guard rest.first == "[", let close = rest.firstIndex(of: "]") else { return nil }
    let inside = String(rest[rest.index(after: rest.startIndex)..<close])
    rest = rest[rest.index(after: close)...]
    return inside
  }
}
