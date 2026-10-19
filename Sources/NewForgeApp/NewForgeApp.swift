import SwiftUI
import NewForgeKit
import Carbon
import ServiceManagement

@main
struct NewForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = PreferencesModel()

    var body: some Scene {
        // The app lives in the menu bar; the preferences window is opened
        // from the status item menu.
        MenuBarExtra("NewForge", systemImage: "doc.badge.plus") {
            MenuBarMenu(model: model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView(model: model)
                .frame(width: 520, height: 460)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let placementHandler = PlacementHandler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerLoginItem()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    /// Launch at login so the URL-scheme handler is always up when the
    /// user right-clicks in Finder. SMAppService is the modern replacement
    /// for the deprecated SMLoginItemSetEnabled.
    private func registerLoginItem() {
        do {
            try SMAppService.mainApp.register()
            NFLog.info("login item registered")
        } catch {
            // Common cause: user previously disabled it in System Settings
            // > General > Login Items. Not fatal - just means we won't
            // auto-launch.
            NFLog.error("login item registration failed: \(error.localizedDescription)")
        }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                         withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        placementHandler.handle(url)
    }
}

struct MenuBarMenu: View {
    @ObservedObject var model: PreferencesModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(verbatim: String(format:
            NSLocalizedString("menubar.enabledCount", value: "%d template types enabled", comment: ""),
            model.templates.count - model.settings.disabledIDs.count))

        Divider()

        Button(NSLocalizedString("menubar.preferences", value: "Preferences\u{2026}", comment: "")) {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }

        Button(NSLocalizedString("menubar.openTemplates", value: "Open Templates Folder", comment: "")) {
            let url = TemplateStore.defaultUserRoot()
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        }

        Button(NSLocalizedString("menubar.howToEnable", value: "How to Enable the Finder Extension\u{2026}", comment: "")) {
            model.showingEnableHelp = true
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button(NSLocalizedString("menubar.quit", value: "Quit NewForge", comment: "")) {
            NSApp.terminate(nil)
        }
    }
}
