import Foundation

/// User preferences shared by the container app and the Finder extension.
///
/// Both processes are sandboxed, so `UserDefaults.standard` would give each
/// its own private domain inside its own container - the app would write
/// preferences the extension could never see. Instead both share the
/// `group.com.newforge` app group (declared in both entitlements files) and
/// read/write the group suite. The app posts `newforgeSettingsChanged`
/// after writing; the extension observes it via Darwin notifications and
/// reloads before building its menu.
///
/// If the group suite is unavailable (e.g. the app group entitlement was
/// not provisioned, which happens with ad-hoc `codesign --sign -` builds
/// where entitlements are ignored) we fall back to `.standard` so the
/// processes still run, just without shared settings.
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

    /// The defaults domain both processes use. App Groups would give a
    /// shared container, but the free personal provisioning profile does
    /// not include com.apple.security.application-groups, so the container
    /// is never actually granted (writes fail with EPERM). We use each
    /// process's own UserDefaults and reconcile via Darwin notification.
    public static var shared: UserDefaults { .standard }

    private enum Key {
        static let alwaysPrompt = "naming.alwaysPrompt"
        static let neverPrompt = "naming.neverPrompt"
        static let autoOpen = "behavior.autoOpen"
        static let disabledIDs = "templates.disabledIDs"
        static let folderBookmarks = "folders.bookmarks"
    }

    public static func load(defaults: UserDefaults = shared) -> Settings {
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


    public static func save(_ settings: Settings, defaults: UserDefaults = shared, notify: Bool = true) {
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
