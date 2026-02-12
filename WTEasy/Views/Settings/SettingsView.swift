import SwiftUI
import WTTerminal

struct SettingsView: View {
    @AppStorage("defaultShell") private var defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    @AppStorage("terminalFontSize") private var terminalFontSize = 13.0
    @AppStorage("terminalThemeId") private var terminalThemeId = TerminalThemes.defaultTheme.id

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

                Picker("Theme", selection: $terminalThemeId) {
                    ForEach(TerminalThemes.allThemes) { theme in
                        HStack(spacing: 8) {
                            ThemeSwatchView(theme: theme)
                            Text(theme.name)
                        }
                        .tag(theme.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .navigationTitle("Settings")
    }
}

private struct ThemeSwatchView: View {
    let theme: TerminalTheme

    var body: some View {
        HStack(spacing: 1) {
            Rectangle()
                .fill(Color(nsColor: theme.background.toNSColor()))
            Rectangle()
                .fill(Color(nsColor: theme.foreground.toNSColor()))
            Rectangle()
                .fill(Color(nsColor: theme.ansiColors[1].toNSColor())) // red
            Rectangle()
                .fill(Color(nsColor: theme.ansiColors[2].toNSColor())) // green
            Rectangle()
                .fill(Color(nsColor: theme.ansiColors[4].toNSColor())) // blue
        }
        .frame(width: 60, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}
