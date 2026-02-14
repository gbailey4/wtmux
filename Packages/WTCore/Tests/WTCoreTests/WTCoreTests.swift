import Testing
@testable import WTCore

@Test func projectCreation() {
    let project = Project(name: "Test", repoPath: "/tmp/test")
    #expect(project.name == "Test")
    #expect(project.isRemote == false)
}

@Test func resolvedIconNameDefaultsToFolderForLocal() {
    let project = Project(name: "Local", repoPath: "/tmp/local")
    #expect(project.resolvedIconName == "folder.fill")
}

@Test func resolvedIconNameDefaultsToGlobeForRemote() {
    let project = Project(name: "Remote", repoPath: "/tmp/remote")
    project.sshHost = "example.com"
    #expect(project.resolvedIconName == "globe")
}

@Test func resolvedIconNameUsesCustomIcon() {
    let project = Project(name: "Custom", repoPath: "/tmp/custom", iconName: "terminal.fill")
    #expect(project.resolvedIconName == "terminal.fill")
}

@Test func colorNameRoundTrip() {
    let project = Project(name: "Colored", repoPath: "/tmp/colored", colorName: "purple")
    #expect(project.colorName == "purple")
}

@Test func iconNameRoundTrip() {
    let project = Project(name: "Iconed", repoPath: "/tmp/iconed", iconName: "cube.fill")
    #expect(project.iconName == "cube.fill")
}

@Test func colorPaletteIsNonEmpty() {
    #expect(!Project.colorPalette.isEmpty)
}

@Test func iconPaletteIsNonEmpty() {
    #expect(!Project.iconPalette.isEmpty)
}
