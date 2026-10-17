import Foundation

/// User preferences shared by the container app and the Finder extension.
///
/// Both processes read plain `UserDefaults.standard` (no app group) so the
/// extension keeps working even without sandbox group containers. The app
/// posts `newforgeSettingsChanged` after writing; the extension observes it
/// via Darwin notifications and reloads before building its menu.
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
}

public enum SettingsStore {

    public static let darwinNotification = "com.newforge.app.settingsChanged"

    private enum Key {
        static let alwaysPrompt = "naming.alwaysPrompt"
        static let neverPrompt = "naming.neverPrompt"
        static let autoOpen = "behavior.autoOpen"
        static let disabledIDs = "templates.disabledIDs"
    }

    public static func load(defaults: UserDefaults = .standard) -> Settings {
        var s = Settings()
        s.alwaysPrompt = defaults.bool(forKey: Key.alwaysPrompt)
        s.neverPrompt = defaults.bool(forKey: Key.neverPrompt)
        // Default true when the key was never written.
        s.autoOpen = defaults.object(forKey: Key.autoOpen) as? Bool ?? true
        if let list = defaults.stringArray(forKey: Key.disabledIDs) {
            s.disabledIDs = Set(list)
        }
        return s
    }

    public static func save(_ settings: Settings, defaults: UserDefaults = .standard, notify: Bool = true) {
        defaults.set(settings.alwaysPrompt, forKey: Key.alwaysPrompt)
        defaults.set(settings.neverPrompt, forKey: Key.neverPrompt)
        defaults.set(settings.autoOpen, forKey: Key.autoOpen)
        defaults.set(Array(settings.disabledIDs), forKey: Key.disabledIDs)
        if notify {
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(darwinNotification as CFString),
                nil, nil, true
            )
        }
    }
}
