import SwiftUI

struct DisclosureChevron: View {
    let open: Bool
    var width: CGFloat = 18

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(open ? 90 : 0))
            .frame(width: width, height: width)
    }
}
