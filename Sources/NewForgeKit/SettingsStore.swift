import Foundation

/// User preferences shared by the container app and the Finder extension.
///
/// The app keeps its canonical JSON in ~/Library/Application Support/NewForge.
/// The Finder extension cannot reliably read that real-home path from its
/// sandbox, so the app also mirrors the JSON into the extension's private
/// container. A Darwin notification tells the extension to reload after a
/// save; this avoids App Group entitlements while keeping data delivery on
/// the same unsandboxed-app side as file creation.
public struct Settings {

    public enum NamingPolicy: String, CaseIterable {
        case prompt      // always ask for a name
        case silent      // never ask, uniquify automatically
        case smart       // ask only when the template opts in (default)
    }

    public var alwaysPrompt = false
    public var neverPrompt = false
    public var autoOpen = true
    /// Template ids the user disabled in Preferences.
    public var disabledIDs = Set<String>()

    public var namingPolicy: NamingPolicy {
        if alwaysPrompt { return .prompt }
        if neverPrompt { return .silent }
        return .smart
    }

    public init() {}

    init(alwaysPrompt: Bool, neverPrompt: Bool, autoOpen: Bool, disabledIDs: Set<String>) {
        self.alwaysPrompt = alwaysPrompt
        self.neverPrompt = neverPrompt
        self.autoOpen = autoOpen
        self.disabledIDs = disabledIDs
    }
}

public enum SettingsStore {

    public static let darwinNotification = "com.newforge.app.settingsChanged"
    private static let extensionBundleID = "com.newforge.app.finderext"

    /// The app's canonical settings file.
    private static var settingsFile: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("NewForge/settings.json")
    }

    /// The extension's readable copy. `applicationSupportDirectory` resolves
    /// inside the appex container when this code runs in the extension.
    private static var extensionSettingsFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("NewForge/settings.json")
    }

    /// The app is unsandboxed and may write directly into the extension's
    /// private container, just as it reads the extension's staging directory
    /// during file creation.
    private static var extensionMirrorFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(extensionBundleID)/Data/Library/Application Support/NewForge/settings.json")
    }

    /// On-disk representation. Keep it flat so hand-editing stays trivial.
    private struct Wire: Codable {
        var alwaysPrompt: Bool
        var neverPrompt: Bool
        var autoOpen: Bool
        var disabledIDs: [String]
    }

    public static func load() -> Settings {
        let url = Bundle.main.bundleIdentifier == extensionBundleID
            ? extensionSettingsFile
            : settingsFile
        guard let data = try? Data(contentsOf: url),
              let wire = try? JSONDecoder().decode(Wire.self, from: data) else {
            return Settings()
        }
        var s = Settings()
        s.alwaysPrompt = wire.alwaysPrompt
        s.neverPrompt = wire.neverPrompt
        s.autoOpen = wire.autoOpen
        s.disabledIDs = Set(wire.disabledIDs)
        return s
    }

    /// Exposed for tests so the context-specific paths above stay testable.
    static func load(from url: URL) -> Settings {
        guard let data = try? Data(contentsOf: url),
              let wire = try? JSONDecoder().decode(Wire.self, from: data) else {
            return Settings()
        }
        return Settings(alwaysPrompt: wire.alwaysPrompt,
                        neverPrompt: wire.neverPrompt,
                        autoOpen: wire.autoOpen,
                        disabledIDs: Set(wire.disabledIDs))
    }

    public static func save(_ settings: Settings, notify: Bool = true) {
        let wire = Wire(alwaysPrompt: settings.alwaysPrompt,
                        neverPrompt: settings.neverPrompt,
                        autoOpen: settings.autoOpen,
                        disabledIDs: Array(settings.disabledIDs))
        guard let data = try? JSONEncoder().encode(wire) else {
            NFLog.error("failed to encode settings")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: settingsFile.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: settingsFile, options: .atomic)
        } catch {
            NFLog.error("failed to save settings: \(error.localizedDescription)")
        }
        if Bundle.main.bundleIdentifier == "com.newforge.app" {
            do {
                try FileManager.default.createDirectory(
                    at: extensionMirrorFile.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try data.write(to: extensionMirrorFile, options: .atomic)
            } catch {
                NFLog.error("failed to mirror settings into extension container: \(error.localizedDescription)")
            }
        }
        if notify {
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(darwinNotification as CFString),
                nil, nil, true
            )
        }
    }

}
