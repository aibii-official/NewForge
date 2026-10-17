import Foundation

/// One entry of a template.json descriptor file. JSON decoding is lenient:
/// any number of unknown keys is ignored, so hand-written descriptors stay
/// forward compatible.
public struct TemplateDescriptor: Codable {
    public var id: String
    public var version: Int
    public var name: [String: String]        // "en" / "zh-Hans" -> display name
    public var fileExtension: String
    public var group: String
    public var icon: String?
    public var defaultName: [String: String]
    public var prompt: Bool                  // ask for a name before creating
    public var openAfterCreate: Bool
    public var kind: String                  // "binary" | "text"
    public var contentFile: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        name = try c.decode([String: String].self, forKey: .name)
        fileExtension = try c.decode(String.self, forKey: .fileExtension)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "other"
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        defaultName = try c.decodeIfPresent([String: String].self, forKey: .defaultName) ?? ["en": "Untitled"]
        prompt = try c.decodeIfPresent(Bool.self, forKey: .prompt) ?? false
        openAfterCreate = try c.decodeIfPresent(Bool.self, forKey: .openAfterCreate) ?? true
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "text"
        contentFile = try c.decodeIfPresent(String.self, forKey: .contentFile)
    }
}

/// A fully resolved template: descriptor + where its content lives on disk.
public struct Template {
    public enum Content {
        /// Copy `url` verbatim after renaming (docx/xlsx/pptx).
        case binary(URL)
        /// Load `url` as UTF-8 text and render placeholders.
        case text(URL)
    }

    public let descriptor: TemplateDescriptor
    public let content: Content
    /// "builtin" or "user" - user templates shadow builtins with the same id.
    public let origin: String

    public var id: String { descriptor.id }
    public var fileExtension: String { descriptor.fileExtension }

    public func localizedName(locale: Locale = .current) -> String {
        Self.pick(descriptor.name, locale: locale) ?? descriptor.id
    }

    public func localizedDefaultName(locale: Locale = .current) -> String {
        Self.pick(descriptor.defaultName, locale: locale) ?? "Untitled"
    }

    static func pick(_ dict: [String: String], locale: Locale) -> String? {
        let code: String
        if #available(macOS 13, *) {
            code = locale.language.languageCode?.identifier ?? "en"
        } else {
            code = locale.languageCode ?? "en"
        }
        if code.hasPrefix("zh") {
            return dict["zh-Hans"] ?? dict["zh"] ?? dict["en"] ?? dict.values.first
        }
        return dict["en"] ?? dict.values.first
    }
}
