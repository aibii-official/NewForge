#if canImport(AppKit)
import AppKit

/// Modal naming sheet used before creating a file. Pure AppKit so it works
/// inside the Finder extension process (no SwiftUI lifecycle available).
public final class NamePanelController: NSObject, NSTextFieldDelegate {

    public struct Request {
        public var templateName: String      // shown in the panel subtitle
        public var fileExtension: String
        public var defaultBaseName: String   // prefilled, base-name part selected

        public init(templateName: String, fileExtension: String, defaultBaseName: String) {
            self.templateName = templateName
            self.fileExtension = fileExtension
            self.defaultBaseName = defaultBaseName
        }
    }

    public enum Result {
        case confirmed(String)   // sanitized base name (no extension)
        case cancelled
    }

    private var panel: NSPanel?
    private var textField: NSTextField?
    private var errorLabel: NSTextField?
    private var okButton: NSButton?
    private var extLabel: NSTextField?
    private var completion: ((Result) -> Void)?
    private var request: Request?

    public override init() { super.init() }

    /// Show the panel centered on screen and call `completion` once.
    public func begin(request: Request, completion: @escaping (Result) -> Void) {
        self.request = request
        self.completion = completion

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 168),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        panel.title = String(format:
            NSLocalizedString("panel.title", value: "New %@", comment: "Naming panel title"),
            request.templateName)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.center()
        self.panel = panel

        let content = NSView(frame: panel.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content

        let promptLabel = NSTextField(labelWithString:
            NSLocalizedString("panel.prompt", value: "File name:", comment: ""))
        promptLabel.frame = NSRect(x: 20, y: 122, width: 380, height: 20)
        promptLabel.font = .systemFont(ofSize: 13, weight: .medium)
        content.addSubview(promptLabel)

        let field = NSTextField(frame: NSRect(x: 20, y: 86, width: 316, height: 26))
        field.stringValue = request.defaultBaseName
        field.delegate = self
        field.font = .systemFont(ofSize: 13)
        content.addSubview(field)
        self.textField = field

        let ext = NSTextField(labelWithString: ".\(request.fileExtension)")
        ext.frame = NSRect(x: 340, y: 89, width: 64, height: 20)
        ext.textColor = .secondaryLabelColor
        ext.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        content.addSubview(ext)
        self.extLabel = ext

        let error = NSTextField(labelWithString: "")
        error.frame = NSRect(x: 20, y: 62, width: 380, height: 16)
        error.textColor = .systemRed
        error.font = .systemFont(ofSize: 11)
        error.isHidden = true
        content.addSubview(error)
        self.errorLabel = error

        let cancel = NSButton(title: NSLocalizedString("panel.cancel", value: "Cancel", comment: ""),
                              target: self, action: #selector(cancelPressed))
        cancel.frame = NSRect(x: 216, y: 16, width: 92, height: 32)
        cancel.keyEquivalent = "\u{1b}"  // Escape
        content.addSubview(cancel)

        let ok = NSButton(title: NSLocalizedString("panel.create", value: "Create", comment: ""),
                          target: self, action: #selector(okPressed))
        ok.frame = NSRect(x: 312, y: 16, width: 92, height: 32)
        ok.keyEquivalent = "\r"          // Return
        ok.bezelStyle = .rounded
        ok.isHighlighted = false
        content.addSubview(ok)
        self.okButton = ok

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)

        // Select the base name without the date suffix, so typing replaces
        // the meaningful part but keeps e.g. " 2026-10-17" if desired.
        if let editor = field.currentEditor() {
            let base = request.defaultBaseName
            editor.selectedRange = NSRange(location: 0, length: base.count)
        }
    }

    @objc private func okPressed() {
        guard let textField else { return }
        do {
            let clean = try FileCreator.sanitizeFileName(textField.stringValue)
            finish(.confirmed(clean))
        } catch let error as LocalizedError {
            showError(error.errorDescription ?? error.localizedDescription)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func cancelPressed() {
        finish(.cancelled)
    }

    public func controlTextDidChange(_ notification: Notification) {
        errorLabel?.isHidden = true
    }

    private func showError(_ message: String) {
        errorLabel?.stringValue = message
        errorLabel?.isHidden = false
        panel?.shake()
    }

    private func finish(_ result: Result) {
        panel?.close()
        panel = nil
        completion?(result)
        completion = nil
    }
}

private extension NSWindow {
    /// Brief horizontal shake to signal a validation error.
    func shake() {
        let original = frame.origin
        let steps: [(CGFloat, TimeInterval)] = [(-8, 0.05), (8, 0.08), (-5, 0.08), (5, 0.08), (0, 0.05)]
        var delay: TimeInterval = 0
        for (dx, duration) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.setFrameOrigin(NSPoint(x: original.x + dx, y: original.y))
            }
            delay += duration
        }
    }
}
#endif
