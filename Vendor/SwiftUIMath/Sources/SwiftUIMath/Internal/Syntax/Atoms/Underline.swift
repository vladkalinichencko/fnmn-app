import Foundation

extension Math {
  final class Underline: Atom {
    var innerList: AtomList?
    /// `\underbrace`: a brace under the base instead of a rule.
    var isBrace = false

    override var finalized: Math.Atom {
      let finalized = super.finalized

      if let underline = finalized as? Underline {
        underline.innerList = underline.innerList?.finalized
      }

      return finalized
    }

    init(_ underline: Underline) {
      self.innerList = underline.innerList.map { AtomList($0) }
      self.isBrace = underline.isBrace
      super.init(underline)
    }

    init(innerList: AtomList? = nil) {
      self.innerList = innerList
      super.init(type: .underline)
    }
  }
}
