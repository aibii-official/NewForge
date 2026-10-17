import Foundation

/// Loads templates from two roots and merges them:
/// 1. the read-only `Resources/Templates` bundled with the app
/// 2. the writable user directory under Application Support
///
/// Each template is a folder containing `template.json` plus its content
/// file. User templates with the same `id` shadow built-in ones; any parse
/// failure is collected in `errors` instead of aborting the whole load.
public final class TemplateStore {

    public struct LoadResult {
        public var templates: [Template]      // sorted, user overrides applied
        public var errors: [String]
    }

    public let builtinRoot: URL
    public let userRoot: URL

    public init(builtinRoot: URL, userRoot: URL) {
        self.builtinRoot = builtinRoot
        self.userRoot = userRoot
    }

    /// Default user-writable template root. Kept in a plain directory (no
    /// sandbox container) so the extension can reach it too.
    public static func defaultUserRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("NewForge/Templates", isDirectory: true)
    }

    public func load(fileManager: FileManager = .default) -> LoadResult {
        var errors: [String] = []
        var byID: [String: Template] = [:]
        var order: [String] = []

        for (root, origin) in [(builtinRoot, "builtin"), (userRoot, "user")] {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            for groupDir in children where groupDir.hasDirectoryPath {
                guard let dirs = try? fileManager.contentsOfDirectory(
                    at: groupDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                ) else { continue }
                for dir in dirs where dir.hasDirectoryPath {
                    switch Self.loadTemplate(at: dir, origin: origin) {
                    case .success(let template):
                        if byID[template.id] == nil { order.append(template.id) }
                        byID[template.id] = template   // later roots override
                    case .failure(let error):
                        errors.append("\(dir.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }

        // Stable menu order: fixed group order first, then declaration order.
        let groupOrder = ["office", "analysis", "dev", "web", "misc", "other"]
        let templates = order.compactMap { byID[$0] }.sorted { a, b in
            let ga = groupOrder.firstIndex(of: a.descriptor.group) ?? groupOrder.count
            let gb = groupOrder.firstIndex(of: b.descriptor.group) ?? groupOrder.count
            let ia = order.firstIndex(of: a.id) ?? 0
            let ib = order.firstIndex(of: b.id) ?? 0
            return ga == gb ? ia < ib : ga < gb
        }
        return LoadResult(templates: templates, errors: errors)
    }

    static func loadTemplate(at dir: URL, origin: String) -> Result<Template, Error> {
        let descriptorURL = dir.appendingPathComponent("template.json")
        guard FileManager.default.fileExists(atPath: descriptorURL.path) else {
            return .failure(CocoaError(.fileNoSuchFile))
        }
        do {
            let data = try Data(contentsOf: descriptorURL)
            let descriptor = try JSONDecoder().decode(TemplateDescriptor.self, from: data)
            let contentFile = descriptor.contentFile ?? "content.\(descriptor.fileExtension)"
            let contentURL = dir.appendingPathComponent(contentFile)
            guard FileManager.default.fileExists(atPath: contentURL.path) else {
                return .failure(CocoaError(.fileNoSuchFile))
            }
            let content: Template.Content = descriptor.kind == "binary" ? .binary(contentURL) : .text(contentURL)
            return .success(Template(descriptor: descriptor, content: content, origin: origin))
        } catch {
            return .failure(error)
        }
    }
}
