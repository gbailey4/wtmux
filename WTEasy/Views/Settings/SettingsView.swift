import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultShell") private var defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    @AppStorage("terminalFontSize") private var terminalFontSize = 13.0

    var body: some View {
        Form {
            Section("Terminal") {
                TextField("Default Shell", text: $defaultShell)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Font Size")
                    Slider(value: $terminalFontSize, in: 10...24, step: 1)
                    Text("\(Int(terminalFontSize))pt")
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .navigationTitle("Settings")
    }
}
