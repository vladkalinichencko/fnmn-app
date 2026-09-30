import Foundation

extension Math {
  final class DisplayProvider: Sendable {
    private struct Cache {
      struct Key: Hashable {
        let latex: String
        let font: Font
        let style: TypesettingStyle
        let proposedWidth: CGFloat
      }

      let atomList = NSCache<NSString, AtomList>()
      let displayNode = NSCache<KeyBox<Key>, DisplayNode>()
    }

    static let shared = DisplayProvider()

    private let cache = ReadWriteLockIsolated<Cache>(Cache())

    func sizeThatFits(
      proposedWidth width: CGFloat,
      latex: String,
      font: Font,
      style: TypesettingStyle
    ) -> CGSize {
      display(
        for: latex,
        font: font,
        style: style,
        proposedWidth: width
      )?.bounds.size ?? .zero
    }

    func display(
      for latex: String,
      font: Font,
      style: TypesettingStyle,
      proposedWidth: CGFloat
    ) -> DisplayNode? {
      cache.withValue { cache in
        let roundedWidth = proposedWidth.halfPointRounded()
        let key = KeyBox(
          Cache.Key(
            latex: latex,
            font: font,
            style: style,
            proposedWidth: roundedWidth
          )
        )

        if let displayNode = cache.displayNode.object(forKey: key) {
          return displayNode
        }

        guard let atomList = atomList(for: latex, cache: &cache) else {
          return nil
        }
        // A formula that fits on one line is never broken. The width it is drawn at comes back rounded to
        // pixels, a hair under the width it measured, and breaking at that width left only the last
        // symbol in view.
        let naturalKey = KeyBox(Cache.Key(latex: latex, font: font, style: style, proposedWidth: 0))
        let natural =
          cache.displayNode.object(forKey: naturalKey)
          ?? Typesetter.createLineForMathList(atomList, font: .init(font: font), style: .init(style), maxWidth: 0)
        if let natural {
          cache.displayNode.setObject(natural, forKey: naturalKey)
        }
        let fits = natural.map { roundedWidth == 0 || $0.width <= roundedWidth + 1 } ?? false
        guard
          let displayNode = fits
            ? natural
            : Typesetter.createLineForMathList(
              atomList,
              font: .init(font: font),
              style: .init(style),
              maxWidth: roundedWidth
            )
        else {
          return nil
        }

        cache.displayNode.setObject(displayNode, forKey: key)

        if displayNode.width != roundedWidth {
          // Cache the measured width to avoid a miss between layout and draw passes
          let secondaryKey = KeyBox(
            Cache.Key(
              latex: latex,
              font: font,
              style: style,
              proposedWidth: displayNode.width.halfPointRounded()
            )
          )
          cache.displayNode.setObject(displayNode, forKey: secondaryKey)
        }

        return displayNode
      }
    }

    private static func source(_ latex: String) -> AtomList {
      let list = AtomList()
      for character in latex {
        let atom = Atom(type: .ordinary, nucleus: String(character))
        atom.fontStyle = .roman
        list.append(atom)
      }
      return list
    }

    private func atomList(for latex: String, cache: inout Cache) -> AtomList? {
      if let atomList = cache.atomList.object(forKey: latex as NSString) {
        return atomList
      }

      // A formula the parser cannot read shows as its source, upright, instead of nothing at all.
      let atomList = Parser.build(fromString: latex) ?? Self.source(latex)
      cache.atomList.setObject(atomList, forKey: latex as NSString)
      return atomList
    }
  }
}

extension Math.Style.Level {
  fileprivate init(_ typesettingStyle: Math.TypesettingStyle) {
    switch typesettingStyle {
    case .display:
      self = .display
    case .text:
      self = .text
    }
  }
}

extension CGFloat {
  fileprivate func halfPointRounded() -> CGFloat {
    guard self > 0 else { return 0 }
    return (self * 2).rounded() / 2
  }
}
