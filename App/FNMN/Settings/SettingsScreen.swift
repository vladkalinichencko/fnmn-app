import SwiftUI

enum ConnectionCheck: Equatable {
    case editing
    case checking
    case connected
    case failed(String)
}

/// The library folder, and the Mac service address and token, saved once and checked with an authorized request.
struct SettingsScreen: View {
    @Environment(LibraryModel.self) private var library
    @Environment(MacLink.self) private var mac
    @Environment(LibraryDialogs.self) private var dialogs
    @State private var address = ""
    @State private var token = ""
    @State private var check = ConnectionCheck.editing

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Folder", value: library.cloudFolder?.lastPathComponent ?? "Not chosen")
                    ChooseLibraryFolderButton(title: "Choose Another Folder")
                } header: {
                    Text("Library")
                } footer: {
                    Text("Every article, video and book lives in this folder in iCloud Drive, and so do the reading places and highlights shared between your devices.")
                }
                Section {
                    TextField("https://", text: $address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Token", text: $token)
                } header: {
                    Text("Mac")
                } footer: {
                    status
                }
                .disabled(check == .checking)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dialogs.send(.dismiss) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", action: saveAndCheck).disabled(check == .checking)
                }
            }
        }
        .onAppear {
            address = mac.connection?.endpoint.absoluteString ?? ""
            token = mac.connection?.token ?? ""
        }
        .onChange(of: address) { check = .editing }
        .onChange(of: token) { check = .editing }
    }

    @ViewBuilder
    private var status: some View {
        switch check {
        case .editing: EmptyView()
        case .checking: ProgressView()
        case .connected: Label("Connected", systemImage: "checkmark.circle")
        case let .failed(message): Text(message)
        }
    }

    private func saveAndCheck() {
        do {
            try mac.save(MacConnection(address: address, token: token))
        } catch {
            check = .failed(error.localizedDescription)
            return
        }
        check = .checking
        Task {
            do {
                try await mac.check()
                check = .connected
            } catch {
                check = .failed(error.localizedDescription)
            }
        }
    }
}
