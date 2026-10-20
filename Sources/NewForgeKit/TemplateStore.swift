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

    /// Default user-writable template root. The extension is sandboxed and
    /// its `~/Library/Application Support` resolves inside its own private
    /// container, so a plain path is NOT shared with the app. The custom
    /// URL scheme the app exposes (see PlacementHandler) lets the extension
    /// ask the app to place files; for templates we instead read from the
    /// user's real Application Support via a security-scoped bookmark that
    /// the user grants the first time they open the Templates folder from
    /// the menu bar.
    public static func defaultUserRoot(fileManager: FileManager = .default) -> URL {
        // Sandboxed appex: containerURL(forSecurityApplicationGroupIdentifier:)
        // would return a path we cannot actually write to because the free
        // provisioning profile drops the entitlement. Skip it entirely.
        // Use homeDirectoryForCurrentUser so the sandboxed extension resolves
        // the REAL ~/Library/Application Support, not its container.
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("NewForge/Templates", isDirectory: true)
    }

    public func load(fileManager: FileManager = .default) -> LoadResult {
        var errors: [String] = []
        var byID: [String: Template] = [:]
        var order: [String] = []

        // The group container is provisioned lazily; until the user drops a
        // template in, the directory legitimately does not exist. Create it
        // so a missing folder is not reported as an error.
        try? fileManager.createDirectory(at: userRoot, withIntermediateDirectories: true)

        for (root, origin) in [(builtinRoot, "builtin"), (userRoot, "user")] {
            NFLog.info("loading templates from \(root.path) (origin=\(origin))")
            guard let children = try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else {
                // A missing user root is expected on a fresh install - the
                // group container is created lazily and the sandboxed
                // extension may not be allowed to mkdir it. Treat as empty.
                if !fileManager.fileExists(atPath: root.path) {
                    NFLog.info("directory does not exist yet, skipping: \(root.path)")
                } else {
                    NFLog.error("cannot read directory \(root.path)")
                }
                continue
            }
            NFLog.info("found \(children.count) children in \(root.path)")

            for groupDir in children where groupDir.hasDirectoryPath {
                guard let dirs = try? fileManager.contentsOfDirectory(
                    at: groupDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                ) else {
                    NFLog.error("cannot read group dir \(groupDir.path)")
                    continue
                }
                for dir in dirs where dir.hasDirectoryPath {
                    switch Self.loadTemplate(at: dir, origin: origin) {
                    case .success(let template):
                        if byID[template.id] == nil { order.append(template.id) }
                        byID[template.id] = template   // later roots override
                        NFLog.info("loaded template \(template.id)")
                    case .failure(let error):
                        errors.append("\(dir.lastPathComponent): \(error.localizedDescription)")
                        NFLog.error("failed to load \(dir.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }

        NFLog.info("total \(byID.count) templates loaded, \(errors.count) errors")
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
