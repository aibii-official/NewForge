import Foundation
import os.log

/// Shared os_log category for every NewForge process (app + Finder
/// extension). Unlike NSLog, messages are not data-protected, so they
/// survive in `log show` and Console.app - which is the only feedback
/// channel available inside a sandboxed Finder Sync extension.
///
/// Filter with:
///   log show --last 1h --predicate 'subsystem == "com.newforge.app"'
public enum NFLog {
    private static let log = OSLog(subsystem: "com.newforge.app", category: "core")

    public static func info(_ message: String) {
        os_log("%{public}@", log: log, type: .info, message)
    }

    public static func error(_ message: String) {
        os_log("%{public}@", log: log, type: .error, message)
    }
}
