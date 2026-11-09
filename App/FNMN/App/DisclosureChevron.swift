import SwiftUI

/// The mark that says a section opens under its heading: the same box either way, and the system's own swap
/// between the two symbols, so nothing is turned inside a frame that was measured for the other one.
struct DisclosureChevron: View {
    let open: Bool
    var width: CGFloat = 18

    var body: some View {
        Image(systemName: open ? "chevron.down" : "chevron.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: width, height: width)
    }
}
