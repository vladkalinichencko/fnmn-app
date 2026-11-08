import FNMNCore
import SwiftUI

struct FindBar: View {
    let reader: ReaderCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        let find = reader.state.find ?? FindState()
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in Material", text: Binding(
                get: { find.query },
                set: { reader.send(.findQuery($0)) }
            ))
            .focused($focused)
            .submitLabel(.search)
            .onSubmit { reader.send(.findStep(1)) }
            Text(count(find))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button {
                reader.send(.findStep(-1))
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(find.current == nil)
            Button {
                reader.send(.findStep(1))
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(find.current == nil)
            Button("Done") { reader.send(.find(false)) }
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.vertical, 8)
        .background(.bar)
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
