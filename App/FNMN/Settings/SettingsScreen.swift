import SwiftUI

enum ConnectionCheck: Equatable {
    case editing
    case checking
    case connected
    case failed(String)
}

/// The library folder, and the server address and token, saved once and checked with an authorized request.
struct SettingsScreen: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ServerLink.self) private var server
    @Environment(LibraryDialogs.self) private var dialogs
    @State private var address = ""
    @State private var token = ""
    @State private var check = ConnectionCheck.editing
    @AppStorage(ReaderAppearance.lineSideKey) private var lineSide = ReadingLineSide.left

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reading Line Handle", selection: $lineSide) {
                        ForEach(ReadingLineSide.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Reading Line Handle")
                } footer: {
                    Text("The edge of the screen where you drag the red reading line from.")
                }
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
                    Text("Server")
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
            let connection = server.savedConnection()
            address = connection?.endpoint.absoluteString ?? ""
            token = connection?.token ?? ""
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
            try server.save(ServerConnection(address: address, token: token))
        } catch {
            check = .failed(error.localizedDescription)
            return
        }
        check = .checking
        Task {
            do {
                try await server.check()
                check = .connected
            } catch {
                check = .failed(error.localizedDescription)
            }
        }
    }
}
