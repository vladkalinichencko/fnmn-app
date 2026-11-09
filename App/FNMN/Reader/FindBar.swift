import FNMNCore
import SwiftUI

struct FindBar: View {
    let reader: ReaderCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        let find = reader.state.find ?? FindState()
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in Text", text: Binding(
                get: { find.query },
                set: { reader.send(.findQuery($0)) }
            ))
            .textFieldStyle(.plain)
            .focused($focused)
            .submitLabel(.search)
            .onSubmit { reader.send(.findStep(1)) }
            Text(count(find))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.numericText())
            Button("Previous Match", systemImage: "chevron.up") { reader.send(.findStep(-1)) }
                .frame(width: 32, height: 44)
                .disabled(find.current == nil)
            Button("Next Match", systemImage: "chevron.down") { reader.send(.findStep(1)) }
                .frame(width: 32, height: 44)
                .disabled(find.current == nil)
            Button("Done", systemImage: "xmark") { reader.send(.find(false)) }
                .frame(width: 32, height: 44)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .padding(.horizontal, 14)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, Tokens.gutter)
        .padding(.vertical, 6)
        .onAppear { focused = true }
    }

    private func count(_ find: FindState) -> String {
        switch find.result {
        case .idle: ""
        case .searching: "Searching…"
        case let .matches(matches, current):
            matches.isEmpty ? "No Matches" : "\(current + 1) of \(matches.count)"
        }
    }
}
