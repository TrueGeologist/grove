import SwiftUI

#if !GROVE_BENCH
@main
struct GroveApp: App {
    @StateObject private var session = GroveSession()
    @StateObject private var language = LanguageStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(language)
                .id(language.choice)
                .onAppear { session.openLaunchPathIfNeeded() }
                .onChange(of: language.choice) { _, _ in
                    session.relocalize()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        Settings {
            LanguageSettingsView()
                .environmentObject(language)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(Copy.aboutMenu) {
                    session.showAbout = true
                }
            }
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text(Copy.settingsMenu)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button(Copy.chooseFolder) {
                    session.chooseFolder()
                }
                .keyboardShortcut("o")
            }
        }
    }
}

struct LanguageSettingsView: View {
    @EnvironmentObject private var language: LanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Copy.language)
                .font(.headline)
            Picker(Copy.language, selection: $language.choice) {
                Text(Copy.languageSystem).tag(AppLanguage.system)
                Text("Русский").tag(AppLanguage.ru)
                Text("English").tag(AppLanguage.en)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text(Copy.languageFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 320, alignment: .leading)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1"
        return "Grove \(short)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(version)
                    .font(.title2.weight(.semibold))
                Text(Copy.aboutBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(Copy.developer)
                    .foregroundStyle(.secondary)
                Text("MaratFly")
            }
            Link(destination: URL(string: "https://github.com/TrueGeologist/grove")!) {
                Label("github.com/TrueGeologist/grove", systemImage: "link")
            }
            HStack {
                Spacer()
                Button(Copy.aboutClose, action: dismiss.callAsFunction)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
#endif
