import SwiftUI

#if !GROVE_BENCH
@main
struct GroveApp: App {
    @StateObject private var session = GroveSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .onAppear { session.openLaunchPathIfNeeded() }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(Copy.chooseFolder) {
                    session.chooseFolder()
                }
                .keyboardShortcut("o")
            }
        }
    }
}
#endif
