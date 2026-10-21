import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Placement strategy used by the sandboxed Finder extension: stage the
/// fully rendered file inside our own container, then hand it to the
/// unsandboxed main app via a custom URL scheme. The app reads the staged
/// file and copies it to the target folder. App Groups cannot be used here
/// because the free personal provisioning profile doesn't include the
/// `com.apple.security.application-groups` entitlement, so the shared
/// container is never actually granted.
public enum FinderPlacement {

    /// URL scheme the main app listens on. Registered in the app's
    /// Info.plist under CFBundleURLTypes.
    public static let urlScheme = "newforge-create"

    private static var stagingRoot: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("com.newforge.staging", isDirectory: true)
    }

    /// Stage `template` under a unique name and ask the app to place it.
    /// Returns the final URL on success, nil if the app is unreachable or
    /// reports an error.
    public static func place(from template: Template, baseName: String, in directory: URL,
                             autoOpen: Bool, timeout: TimeInterval = 10) throws -> URL? {
        let staged = try stage(template: template, baseName: baseName, directory: directory)
        defer { try? FileManager.default.removeItem(at: staged) }
        return try askAppViaURLScheme(staged: staged,
                                      baseName: baseName,
                                      fileExtension: template.fileExtension,
                                      into: directory,
                                      autoOpen: autoOpen,
                                      timeout: timeout)
    }

    // MARK: - private

    private static func stage(template: Template, baseName: String, directory: URL) throws -> URL {
        let fm = FileManager.default
        let root = stagingRoot
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { reapStale() }

        let name = "\(UUID().uuidString)-\(baseName).\(template.fileExtension)"
        let dest = root.appendingPathComponent(name)

        switch template.content {
        case .binary(let source):
            // `copyItem` of a code-signed bundle resource can produce a file
            // clone that the unsandboxed app cannot open across the container
            // boundary. Read the bytes explicitly so the staged payload is a
            // plain, fully materialized file just like the text path below.
            let data = try Data(contentsOf: source, options: [.mappedIfSafe])
            try data.write(to: dest, options: .atomic)
            NFLog.info("staged binary \(dest.path) (\(data.count) bytes)")
        case .text(let source):
            guard let raw = try? String(contentsOf: source, encoding: .utf8) else {
                throw CreateError.unreadableTemplate(source.path)
            }
            let context = FileCreator.filenameContext(template: template,
                                                      confirmedBase: baseName,
                                                      directory: directory)
            let rendered = TemplateRenderer.render(raw, context: context)
            try rendered.write(to: dest, atomically: true, encoding: .utf8)
        }
        return dest
    }

    /// Hand the staged file to the main app via a `newforge-create://` URL.
    /// The app replies asynchronously by writing the final path (or an
    /// error) to a sidecar file in the staging directory, which we poll for.
    private static func askAppViaURLScheme(staged: URL,
                                           baseName: String,
                                           fileExtension: String,
                                           into directory: URL,
                                           autoOpen: Bool,
                                           timeout: TimeInterval) throws -> URL? {
        // Reply channel: a fixed path inside the staging area, keyed by the
        // staged file's unique name. The app writes the result there.
        let replyPath = stagingRoot.appendingPathComponent("\(staged.lastPathComponent).reply")

        var comps = URLComponents()
        comps.scheme = urlScheme
        comps.host = "place"
        comps.queryItems = [
            URLQueryItem(name: "staged", value: staged.path),
            URLQueryItem(name: "name", value: baseName),
            URLQueryItem(name: "ext", value: fileExtension),
            URLQueryItem(name: "dir", value: directory.path),
            URLQueryItem(name: "reply", value: replyPath.path),
            URLQueryItem(name: "open", value: autoOpen ? "1" : "0"),
        ]
        guard let url = comps.url else {
            throw NSError(domain: "NewForge.Placement", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "could not build callback URL"])
        }
        NFLog.info("creation: posting \(url.absoluteString.prefix(120))…")
#if canImport(AppKit)
        NSWorkspace.shared.open(url)
#else
        // NewForgeKit is also used in the headless `make test` runner; in
        // that context there is no app to talk to, so we just fail.
        return nil
#endif

        // Wait for the reply file to appear. The app writes it on success
        // (first line = final path) or failure (first line starts with "!").
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? String(contentsOf: replyPath, encoding: .utf8) {
                try? FileManager.default.removeItem(at: replyPath)
                let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("!") {
                    throw NSError(domain: "NewForge.Placement", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: String(trimmed.dropFirst())])
                }
                guard !trimmed.isEmpty else { return nil }
                return URL(fileURLWithPath: trimmed)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        NFLog.error("creation: timed out waiting for app reply at \(replyPath.path)")
        return nil
    }

    private static func reapStale(maxAge: TimeInterval = 3600) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: stagingRoot,
                                                      includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for url in items {
            if let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               mtime < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }
}
