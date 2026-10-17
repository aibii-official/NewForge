import Cocoa
import FinderSync
import NewForgeKit

/// Finder Sync extension entry point.
///
/// Responsibilities:
/// - claim every folder (`directoryURLs = /`) so the menu appears anywhere
///   Finder shows a contextual menu
/// - build the "New File" submenu from templates on disk
/// - honor the modifier flags: Option forces the naming panel, Control
///   forces silent creation
/// - create the file, reveal it in Finder and optionally open it
final class FinderSync: FIFinderSync {

    private var templates: [Template] = []
    private var settings = Settings()
    private var namePanel: NamePanelController?

    private lazy var store: TemplateStore = {
        let builtin = Bundle.main.resourceURL?
            .appendingPathComponent("Templates", isDirectory: true)
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Templates", isDirectory: true)
        return TemplateStore(builtinRoot: builtin, userRoot: TemplateStore.defaultUserRoot())
    }()

    override init() {
        super.init()

        // Claim everything: menu should appear in every folder, on the
        // desktop and on background right-clicks.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]

        reloadState()

        // Re-read settings whenever the container app saves them.
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<FinderSync>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { me.reloadState() }
            },
            SettingsStore.darwinNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func reloadState() {
        settings = SettingsStore.load()
        let result = store.load()
        templates = result.templates
        if !result.errors.isEmpty {
            NSLog("NewForge: template load errors: %@", result.errors.joined(separator: "; "))
        }
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

        let rootTitle = NSLocalizedString("menu.root", value: "New File", comment: "Root menu title")
        let rootItem = NSMenuItem(title: rootTitle, action: nil, keyEquivalent: "")
        if #available(macOS 11.0, *) {
            rootItem.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
        }

        let submenu = NSMenu(title: rootTitle)
        let enabled = templates.filter { !settings.disabledIDs.contains($0.id) }

        if enabled.isEmpty {
            let empty = NSMenuItem(
                title: NSLocalizedString("menu.empty", value: "No Templates Available", comment: ""),
                action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for template in enabled {
                let item = NSMenuItem(
                    title: menuTitle(for: template),
                    action: #selector(createFromTemplate(_:)),
                    keyEquivalent: "")
                item.target = self
                item.representedObject = template.id
                item.tag = templates.firstIndex(where: { $0.id == template.id }) ?? 0
                if #available(macOS 11.0, *), let icon = template.descriptor.icon {
                    item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
                }
                submenu.addItem(item)
            }

            // Modifier hint, like Finder's own alternative items.
            submenu.addItem(.separator())
            let hint = NSMenuItem(
                title: NSLocalizedString("menu.hint",
                    value: "Hold Option to rename, Control for instant create",
                    comment: "Modifier hint, disabled item"),
                action: nil, keyEquivalent: "")
            hint.isEnabled = false
            if #available(macOS 14.0, *) {
                // Section headers render as small gray captions.
                submenu.addItem(.sectionHeader(title: ""))
            }
            submenu.addItem(hint)
        }

        rootItem.submenu = submenu
        menu.addItem(rootItem)
        return menu
    }

    private func menuTitle(for template: Template) -> String {
        let name = template.localizedName()
        switch effectiveNamingPolicy(for: template) {
        case .prompt:
            return String(format: NSLocalizedString("menu.item.prompt",
                value: "%@\u{2026}", comment: "Item that will ask for a name"), name)
        case .silent, .smart:
            return name
        }
    }

    private func effectiveNamingPolicy(for template: Template) -> Settings.NamingPolicy {
        let flags = NSEvent.modifierFlags
        if flags.contains(.control) { return .silent }
        if flags.contains(.option) { return .prompt }
        return settings.namingPolicy
    }

    // MARK: - Action

    @objc private func createFromTemplate(_ sender: NSMenuItem) {
        reloadState()   // pick up any template edits since the menu opened
        guard let template = templates.first(where: { $0.id == sender.representedObject as? String }) else {
            return
        }
        guard let directory = targetDirectory() else {
            NSSound.beep()
            return
        }

        switch effectiveNamingPolicy(for: template) {
        case .prompt:
            presentNamePanel(for: template, in: directory)
        case .silent:
            let base = FileCreator.defaultBaseName(for: template, directory: directory)
            create(template, baseName: base, in: directory)
        case .smart:
            if template.descriptor.prompt {
                presentNamePanel(for: template, in: directory)
            } else {
                let base = FileCreator.defaultBaseName(for: template, directory: directory)
                create(template, baseName: base, in: directory)
            }
        }
    }

    private func targetDirectory() -> URL? {
        let controller = FIFinderSyncController.default()
        if let target = controller.targetedURL() { return target }
        if let selected = controller.selectedItemURLs()?.first {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: selected.path, isDirectory: &isDir), isDir.boolValue {
                return selected
            }
            return selected.deletingLastPathComponent()
        }
        return nil
    }

    private func presentNamePanel(for template: Template, in directory: URL) {
        let panel = NamePanelController()
        self.namePanel = panel   // retain for the panel's lifetime
        let request = NamePanelController.Request(
            templateName: template.localizedName(),
            fileExtension: template.fileExtension,
            defaultBaseName: FileCreator.defaultBaseName(for: template, directory: directory)
        )
        panel.begin(request: request) { [weak self, weak panel] result in
            defer { self?.namePanel = nil }
            guard case .confirmed(let base) = result else { return }
            _ = panel   // keep alive until the callback fires
            self?.create(template, baseName: base, in: directory)
        }
    }

    private func create(_ template: Template, baseName: String, in directory: URL) {
        do {
            let url = try FileCreator.create(from: template, baseName: baseName, in: directory)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            if settings.autoOpen, template.descriptor.openAfterCreate {
                if #available(macOS 10.15, *) {
                    NSWorkspace.shared.open(url)
                } else {
                    NSWorkspace.shared.openFile(url.path)
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("alert.createFailed",
                value: "Could Not Create File", comment: "")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
