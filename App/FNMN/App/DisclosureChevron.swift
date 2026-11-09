import SwiftUI

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
