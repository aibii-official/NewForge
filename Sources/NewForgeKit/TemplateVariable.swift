import Foundation

/// Variables usable inside `{{ ... }}` placeholders in text templates,
/// filenames and template metadata (name / prompt / defaultName).
public enum TemplateVariable: String, CaseIterable {
    case filename          // final file name without extension
    case date              // yyyy-MM-dd
    case time              // HH-mm
    case datetime          // yyyy-MM-dd HH:mm
    case year, month, day  // zero-padded components
    case user              // current macOS login name
    case dirname           // name of the destination folder

    static let calendar = Calendar(identifier: .gregorian)

    /// Look up the rendered value for a raw placeholder key.
    static func resolve(_ key: String, context: RenderContext) -> String {
        switch key {
        case "filename": return context.filename
        case "dirname": return context.dirname
        case "user": return NSUserName()
        default:
            return dateValue(key: key, now: context.now)
        }
    }

    private static func dateValue(key: String, now: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let y = comps.year ?? 0, mo = comps.month ?? 0, d = comps.day ?? 0
        let h = comps.hour ?? 0, mi = comps.minute ?? 0
        switch key {
        case "date": return String(format: "%04d-%02d-%02d", y, mo, d)
        case "time": return String(format: "%02d-%02d", h, mi)
        case "datetime": return String(format: "%04d-%02d-%02d %02d:%02d", y, mo, d, h, mi)
        case "year": return String(format: "%04d", y)
        case "month": return String(format: "%02d", mo)
        case "day": return String(format: "%02d", d)
        default: return ""  // unknown key: leave handling to caller
        }
    }

    /// Sorted longest-first so `datetime` is consumed before `date` during
    /// longest-prefix replacement.
    static let keysLongestFirst: [String] = {
        allCases.map { $0.rawValue }.sorted { $0.count > $1.count }
    }()
}
