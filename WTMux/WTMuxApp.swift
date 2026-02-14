import SwiftUI
import SwiftData
import WTCore
import os.log

private let logger = Logger(subsystem: "com.wtmux", category: "App")

@main
struct WTMuxApp: App {
    let modelContainer: ModelContainer
    private let initError: String?

    init() {
        do {
            let schema = Schema([
                Project.self,
                Worktree.self,
                ProjectProfile.self,
                RunConfiguration.self,
            ])
            // Name kept as "WTEasy" for backward compatibility with existing data stores
            let config = ModelConfiguration("WTEasy", isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            initError = nil
        } catch {
            logger.error("Failed to create persistent ModelContainer: \(error.localizedDescription). Falling back to in-memory store.")
            // Fall back to an in-memory container so the app can still launch
            // and show an error banner rather than crashing.
            let schema = Schema([
                Project.self,
                Worktree.self,
                ProjectProfile.self,
                RunConfiguration.self,
            ])
            // swiftlint and force-try: the in-memory config cannot fail for
            // schema-only initialization, so this is safe.
            modelContainer = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            initError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let initError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                    Text("Database Error")
                        .font(.title2.bold())
                    Text("WTMux could not open its data store. Your data may not be saved.")
                        .multilineTextAlignment(.center)
                    Text(initError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    ContentView()
                }
                .padding()
            } else {
                ContentView()
            }
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
        }
    }
}
