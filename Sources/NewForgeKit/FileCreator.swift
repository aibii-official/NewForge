import Foundation

public enum CreateError: Error, LocalizedError {
    case emptyName
    case invalidName
    case unreadableTemplate(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return NSLocalizedString("error.emptyName", value: "The file name is empty.", comment: "")
        case .invalidName:
            return NSLocalizedString("error.invalidName", value: "The file name contains characters that are not allowed.", comment: "")
        case .unreadableTemplate(let path):
            return String(format: NSLocalizedString("error.unreadableTemplate", value: "Cannot read template: %@", comment: ""), path)
        }
    }
}

public enum FileCreator {

    public static let maxNameLength = 255

    /// Trim whitespace and reject names Finder would refuse anyway.
    public static func sanitizeFileName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CreateError.emptyName }
        guard name != ".", name != ".." else { throw CreateError.invalidName }
        guard !name.contains("/"), !name.contains(":"), !name.contains("\0") else {
            throw CreateError.invalidName
        }
        guard name.count <= maxNameLength else { throw CreateError.invalidName }
        return name
    }

    /// Append " 2", " 3", ... to the base name until the candidate is free.
    public static func uniquifiedURL(for baseName: String, ext: String, in directory: URL,
                                     fileManager: FileManager = .default) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    /// Given the base name the user confirmed, invert the template's
    /// default-name pattern to find what `{{filename}}` should render as.
    ///
    /// Example: pattern "Untitled {{date}}", base "Untitled 2026-10-17"
    /// yields filename = "Untitled 2026-10-17" (filename is not part of the
    /// pattern, so the whole base is used). If the pattern itself contains
    /// `{{filename}}`, e.g. "report-{{filename}}", the middle is extracted.
    public static func filenameContext(template: Template, confirmedBase: String,
                                       directory: URL, now: Date = Date()) -> RenderContext {
        let pattern = template.localizedDefaultName()
        var filename = confirmedBase

        if let key = TemplateRenderer.firstVariable(in: pattern), key != "filename" {
            // Split the pattern around its single placeholder into literal
            // prefix/suffix, then strip them from the confirmed base.
            let placeholder = "{{\(key)}}"
            let parts = pattern.components(separatedBy: placeholder)
            if parts.count == 2 {
                var base = confirmedBase
                if !parts[0].isEmpty, base.hasPrefix(parts[0]) { base.removeFirst(parts[0].count) }
                if !parts[1].isEmpty, base.hasSuffix(parts[1]) { base.removeLast(parts[1].count) }
                if !base.isEmpty { filename = base }
            }
        }

        return RenderContext(
            filename: filename,
            dirname: directory.lastPathComponent,
            now: now
        )
    }

    /// Create the file on disk. Returns the final URL. Never overwrites an
    /// existing file - callers pass an already uniquified base name or we
    /// uniquify here as a safety net.
    @discardableResult
    public static func create(from template: Template, baseName: String, in directory: URL,
                              now: Date = Date(), fileManager: FileManager = .default) throws -> URL {
        let clean = try sanitizeFileName(baseName)
        let dest = uniquifiedURL(for: clean, ext: template.fileExtension, in: directory, fileManager: fileManager)

        switch template.content {
        case .binary(let source):
            try fileManager.copyItem(at: source, to: dest)
        case .text(let source):
            guard let raw = try? String(contentsOf: source, encoding: .utf8) else {
                throw CreateError.unreadableTemplate(source.path)
            }
            let context = filenameContext(template: template, confirmedBase: clean, directory: directory, now: now)
            let rendered = TemplateRenderer.render(raw, context: context)
            try rendered.write(to: dest, atomically: true, encoding: .utf8)
        }
        return dest
    }

    /// Render the default base name (with date variables resolved) used for
    /// silent creation and as the prefilled value of the naming panel.
    public static func defaultBaseName(for template: Template, directory: URL, now: Date = Date()) -> String {
        let context = RenderContext(filename: "", dirname: directory.lastPathComponent, now: now)
        return TemplateRenderer.render(template.localizedDefaultName(), context: context)
    }
}
