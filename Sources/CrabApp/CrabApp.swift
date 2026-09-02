import AppKit
import CrabAppSupport
import SwiftUI

@main
struct CrabDesktopApp: App {
    @StateObject private var model = AppModel()
    @AppStorage(CrabLanguagePreference.defaultsKey)
    private var languagePreference = CrabLanguagePreference.system.rawValue

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Crab", id: "main") {
            MainView(model: model)
                .id(languagePreference)
                .environment(\.locale, interfaceLocale)
                .frame(
                    minWidth: 1060,
                    idealWidth: 1120,
                    maxWidth: .infinity,
                    minHeight: 720,
                    idealHeight: 780,
                    maxHeight: .infinity
                )
        }
        .defaultPosition(.center)
        .defaultSize(width: 1120, height: 780)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuPanel(model: model)
                .id(languagePreference)
                .environment(\.locale, interfaceLocale)
        } label: {
            Image(nsImage: MenuBarLogoIcon.image)
                .accessibilityLabel("Crab")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            CrabSettingsView()
                .id(languagePreference)
                .environment(\.locale, interfaceLocale)
        }
    }

    private var interfaceLocale: Locale {
        let language = CrabLanguagePreference(storedValue: languagePreference)
            .resolve(preferredLanguages: Locale.preferredLanguages)
        return Locale(identifier: language.rawValue)
    }
}

extension Color {
    static let crabPurple = Color(red: 101 / 255, green: 88 / 255, blue: 211 / 255)
    static let crabLavender = Color(red: 244 / 255, green: 242 / 255, blue: 253 / 255)
    static let crabBackground = Color(red: 250 / 255, green: 249 / 255, blue: 252 / 255)
    static let crabInk = Color(red: 39 / 255, green: 37 / 255, blue: 53 / 255)
}
