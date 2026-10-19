import AppKit
import Foundation
import NewForgeKit

/// Receives `newforge-create://place?...` URLs from the sandboxed Finder
/// extension, copies the staged payload to the requested folder and writes
/// a one-line reply file the extension polls for.
///
/// Security notes:
/// - The `staged` path must live inside the extension's own caches
///   container; anything else is refused.
/// - The destination is uniquified (`name 2.ext`, ...) to avoid clobbering
///   an existing file.
final class PlacementHandler {

    func handle(_ url: URL) {
        guard url.scheme == FinderPlacement.urlScheme, url.host == "place" else {
            NFLog.error("placement: unrecognized url \(url.absoluteString)")
            return
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        guard let stagedPath = value("staged"),
              let baseName = value("name"),
              let fileExtension = value("ext"),
              let directoryPath = value("dir"),
              let replyPath = value("reply") else {
            NFLog.error("placement: missing query items in \(url.absoluteString)")
            return
        }
        let autoOpen = value("open") == "1"

        NFLog.info("placement: \(baseName).\(fileExtension) into \(directoryPath)")

        let staged = URL(fileURLWithPath: stagedPath)
        let directory = URL(fileURLWithPath: directoryPath)
        let reply = URL(fileURLWithPath: replyPath)

        do {
            // The extension stages inside its own sandbox container:
            //   ~/Library/Containers/com.newforge.app.finderext/Data/Library/Caches/com.newforge.staging/
            // The (unsandboxed) app's own cachesDirectory resolves to
            //   ~/Library/Caches/
            // which is a different location, so a naive prefix check against
            // the app's staging root would always reject. We only require
            // the staged file to live inside the extension's container.
            let extensionContainer = NSHomeDirectory()
                .appending("/Library/Containers/com.newforge.app.finderext/Data/")
            guard staged.path.hasPrefix(extensionContainer) else {
                try "!refusing to read outside the extension container".write(to: reply, atomically: true, encoding: .utf8)
                return
            }
            let dest = FileCreator.uniquifiedURL(for: baseName, ext: fileExtension, in: directory)
            try FileManager.default.copyItem(at: staged, to: dest)
            NFLog.info("placement: placed at \(dest.path)")
            if autoOpen {
                // Do the open here: the app is not sandboxed, so this won't
                // trigger a TCC prompt. The extension calling open() itself
                // would be blocked (the "no permission to open" dialog).
                NSWorkspace.shared.open(dest)
            }
            try dest.path.write(to: reply, atomically: true, encoding: .utf8)
        } catch {
            NFLog.error("placement: failed: \(error.localizedDescription)")
            try? "!\(error.localizedDescription)".write(to: reply, atomically: true, encoding: .utf8)
        }
    }
}
