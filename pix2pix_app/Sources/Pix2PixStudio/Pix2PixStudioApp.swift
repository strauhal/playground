import SwiftUI

@main
struct Pix2PixStudioApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Image…") { appState.chooseInputImage() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .importExport) {
                Button("Reveal Output Folder") { appState.revealOutputFolder() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
