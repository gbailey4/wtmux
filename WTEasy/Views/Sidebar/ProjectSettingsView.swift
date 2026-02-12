import SwiftUI
import WTCore

struct ProjectSettingsView: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var repoPath: String
    @State private var defaultBranch: String
    @State private var worktreeBasePath: String
    @State private var isRemote: Bool
    @State private var sshHost: String
    @State private var sshUser: String
    @State private var sshPort: String

    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.name)
        _repoPath = State(initialValue: project.repoPath)
        _defaultBranch = State(initialValue: project.defaultBranch)
        _worktreeBasePath = State(initialValue: project.worktreeBasePath)
        _isRemote = State(initialValue: project.isRemote)
        _sshHost = State(initialValue: project.sshHost ?? "")
        _sshUser = State(initialValue: project.sshUser ?? "")
        _sshPort = State(initialValue: project.sshPort.map(String.init) ?? "22")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Repository") {
                    TextField("Project Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    TextField("Repository Path", text: $repoPath)
                        .textFieldStyle(.roundedBorder)

                    TextField("Default Branch", text: $defaultBranch)
                        .textFieldStyle(.roundedBorder)

                    TextField("Worktree Base Path", text: $worktreeBasePath)
                        .textFieldStyle(.roundedBorder)
                        .help("Directory where worktrees will be created")
                }

                Section("Connection") {
                    Toggle("Remote (SSH)", isOn: $isRemote)

                    if isRemote {
                        TextField("SSH Host", text: $sshHost)
                            .textFieldStyle(.roundedBorder)
                        TextField("SSH User", text: $sshUser)
                            .textFieldStyle(.roundedBorder)
                        TextField("SSH Port", text: $sshPort)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || repoPath.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    private func save() {
        project.name = name
        project.repoPath = repoPath
        project.defaultBranch = defaultBranch
        project.worktreeBasePath = worktreeBasePath

        if isRemote {
            project.sshHost = sshHost.isEmpty ? nil : sshHost
            project.sshUser = sshUser.isEmpty ? nil : sshUser
            project.sshPort = Int(sshPort) ?? 22
        } else {
            project.sshHost = nil
            project.sshUser = nil
            project.sshPort = nil
        }
    }
}
