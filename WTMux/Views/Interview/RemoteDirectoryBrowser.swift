import SwiftUI
import WTTransport

enum RemoteBrowseTarget: Identifiable {
    case repoPath
    case worktreeBasePath

    var id: String {
        switch self {
        case .repoPath: "repoPath"
        case .worktreeBasePath: "worktreeBasePath"
        }
    }

    var title: String {
        switch self {
        case .repoPath: "Select Repository"
        case .worktreeBasePath: "Select Worktree Directory"
        }
    }
}

struct RemoteDirectoryBrowser: View {
    let transport: CommandTransport
    let title: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var currentPath = ""
    @State private var pathInput = ""
    @State private var directories: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(title)
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            // Path input
            HStack {
                TextField("Path", text: $pathInput)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { navigateTo(pathInput) }
                Button("Go") { navigateTo(pathInput) }
                    .disabled(pathInput.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // Directory listing
            Group {
                if isLoading {
                    Spacer()
                    ProgressView("Loading...")
                    Spacer()
                } else if let errorMessage {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.yellow)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    List {
                        if currentPath != "/" {
                            Button {
                                navigateUp()
                            } label: {
                                Label("..", systemImage: "folder")
                            }
                        }
                        ForEach(directories, id: \.self) { dir in
                            Button {
                                let newPath = currentPath.hasSuffix("/")
                                    ? "\(currentPath)\(dir)"
                                    : "\(currentPath)/\(dir)"
                                navigateTo(newPath)
                            } label: {
                                Label(dir, systemImage: "folder")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Current path display + action buttons
            HStack {
                Text(currentPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Select") { onSelect(currentPath) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(currentPath.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 450)
        .task {
            await fetchHomeDirectory()
        }
    }

    private func navigateTo(_ path: String) {
        let cleaned = path.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }
        Task { await listDirectory(cleaned) }
    }

    private func navigateUp() {
        guard currentPath != "/" else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        navigateTo(parent.isEmpty ? "/" : parent)
    }

    private func fetchHomeDirectory() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await transport.execute("echo $HOME", in: nil)
            let home = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.succeeded, !home.isEmpty {
                await listDirectory(home)
            } else {
                await listDirectory("/")
            }
        } catch {
            await listDirectory("/")
        }
    }

    private func listDirectory(_ path: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await transport.execute("ls -1pA \(shellQuote(path)) 2>/dev/null", in: nil)
            if result.succeeded {
                let entries = result.stdout
                    .components(separatedBy: .newlines)
                    .filter { $0.hasSuffix("/") }
                    .map { String($0.dropLast()) } // strip trailing /
                    .filter { !$0.isEmpty }
                    .sorted()

                currentPath = path
                pathInput = path
                directories = entries
            } else {
                errorMessage = "Cannot access \(path)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
