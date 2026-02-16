import SwiftUI
import WTTransport

struct RemoteSetupSheet: View {
    let transport: CommandTransport
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var setupService = RemoteClaudeSetupService()
    @State private var showScriptContents = false
    @State private var hookScript: String = RemoteClaudeSetupService.hookScriptContent() ?? "(not found)"
    @State private var mcpScript: String = RemoteClaudeSetupService.mcpScriptContent() ?? "(not found)"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)

                    Text("Set Up Claude Integration on Remote Server")
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    // What gets installed
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("What gets deployed", systemImage: "arrow.up.doc")
                                .font(.subheadline.bold())

                            VStack(alignment: .leading, spacing: 4) {
                                bulletItem("~/.wtmux/bin/wtmux-mcp.py", detail: "MCP server for project configuration")
                                bulletItem("~/.wtmux/bin/wtmux-hook.py", detail: "Hook script for activity status tracking")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Config files modified", systemImage: "doc.badge.gearshape")
                                .font(.subheadline.bold())

                            VStack(alignment: .leading, spacing: 4) {
                                bulletItem("~/.claude.json", detail: "Adds wtmux MCP server entry")
                                bulletItem("~/.claude/settings.json", detail: "Adds hook entries for 6 event types")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("Scripts have zero external dependencies and only require Python 3.6+.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Script contents disclosure
                    DisclosureGroup("Show script contents", isExpanded: $showScriptContents) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("wtmux-hook.py")
                                .font(.caption.bold())
                            ScrollView(.horizontal) {
                                Text(hookScript)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 200)

                            Divider()

                            Text("wtmux-mcp.py")
                                .font(.caption.bold())
                            ScrollView(.horizontal) {
                                Text(mcpScript)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 200)
                        }
                        .padding(.top, 8)
                    }
                    .font(.subheadline)

                    // Status area
                    statusView
                }
                .padding(24)
            }

            Divider()

            // Action buttons
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                actionButton
            }
            .padding()
        }
        .frame(width: 500, height: 560)
        .task {
            await setupService.checkPrerequisites(transport: transport)
        }
    }

    @ViewBuilder
    private func bulletItem(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.caption, design: .monospaced))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch setupService.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking remote server...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .needsSetup:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Python 3 found. Ready to set up.")
                    .font(.subheadline)
            }
            if !setupService.claudeCodeDetected {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.orange)
                    Text("Claude Code not yet installed on the server. Scripts will activate once it's installed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .alreadySetup:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Claude integration is already set up and up to date.")
                    .font(.subheadline)
            }
        case .deploying(let step):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(step)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .completed:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Setup completed successfully!")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Setup failed")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch setupService.state {
        case .idle, .checking:
            Button("Set Up") {}
                .disabled(true)
        case .needsSetup:
            Button("Set Up") {
                Task {
                    await setupService.performFullSetup(transport: transport)
                }
            }
            .keyboardShortcut(.defaultAction)
        case .alreadySetup:
            Button("Done") { onComplete() }
                .keyboardShortcut(.defaultAction)
        case .deploying:
            Button("Setting Up...") {}
                .disabled(true)
        case .completed:
            Button("Done") { onComplete() }
                .keyboardShortcut(.defaultAction)
        case .failed:
            Button("Retry") {
                Task {
                    await setupService.performFullSetup(transport: transport)
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
