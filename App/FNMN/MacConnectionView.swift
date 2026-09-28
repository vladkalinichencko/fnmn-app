import SwiftUI

struct MacConnectionView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    @State private var allowsInsecureLAN = false
    @State private var checkState = CheckState.idle

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section("Mac service") {
                    TextField("HTTPS address", text: $address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Bearer token", text: $token)
                    Toggle("Allow HTTP on local network", isOn: $allowsInsecureLAN)
                }
                .disabled(checkState == .checking)
                SwiftUI.Section {
                    Button("Save and check connection") { saveAndCheck() }
                        .disabled(checkState == .checking)
                    switch checkState {
                    case .idle: EmptyView()
                    case .checking: ProgressView("Checking Mac…")
                    case .connected: Label("Connected", systemImage: "checkmark.circle")
                    case let .failed(message): Text(message).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Mac connection")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            guard let connection = library.macConnection else { return }
            address = connection.endpoint.absoluteString
            token = connection.token
            allowsInsecureLAN = connection.allowsInsecureLAN
        }
        .onChange(of: address) { _, _ in checkState = .idle }
        .onChange(of: token) { _, _ in checkState = .idle }
        .onChange(of: allowsInsecureLAN) { _, _ in checkState = .idle }
    }

    private func saveAndCheck() {
        do {
            let connection = try MacConnection(address: address, token: token, allowsInsecureLAN: allowsInsecureLAN)
            try library.saveMacConnection(connection)
            checkState = .checking
            Task {
                do {
                    try await library.checkMacConnection()
                    checkState = .connected
                } catch {
                    checkState = .failed(error.localizedDescription)
                }
            }
        } catch {
            checkState = .failed(error.localizedDescription)
        }
    }
}

private enum CheckState: Equatable {
    case idle
    case checking
    case connected
    case failed(String)
}
