import SwiftUI
import SwiftData
import WTCore

@main
struct WTEasyApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                Project.self,
                Worktree.self,
                ProjectProfile.self,
                RunConfiguration.self,
            ])
            let config = ModelConfiguration("WTEasy", isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
    }
}
