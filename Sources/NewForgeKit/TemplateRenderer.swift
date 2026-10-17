import Foundation

/// Everything the renderer needs to know about where a file is being created.
public struct RenderContext {
    public var filename: String      // base name chosen for the file (no extension)
    public var dirname: String       // name of the destination folder
    public var now: Date

    public init(filename: String, dirname: String, now: Date = Date()) {
        self.filename = filename
        self.dirname = dirname
        self.now = now
    }
}

public enum TemplateRenderer {

    /// Replace every known `{{key}}` in `text`. Unknown placeholders are
    /// left untouched so users can keep literal braces in templates.
    public static func render(_ text: String, context: RenderContext) -> String {
        var result = text
        for key in TemplateVariable.keysLongestFirst {
            let placeholder = "{{\(key)}}"
            guard result.contains(placeholder) else { continue }
            let value = TemplateVariable.resolve(key, context: context)
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        return result
    }

    /// Extract the first known `{{key}}` found in a default-name pattern,
    /// used to turn the placeholder into a regex capture group.
    static func firstVariable(in pattern: String) -> String? {
        for key in TemplateVariable.keysLongestFirst {
            if pattern.contains("{{\(key)}}") { return key }
        }
        return nil
    }
}
