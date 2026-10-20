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
// NSExtensionMain looks up the principal class by the name in Info.plist.
// For Swift classes that name is "<Module>.<Class>" ( Apple's official Finder
// Sync template writes ___VARIABLE_moduleNamePrefixForClasses:XML___FinderSync
// which expands to e.g. "MyExt.FinderSync"). We declare the class with
// @objc(FinderSync) to give it a stable ObjC name and mark it public so the
// symbol is visible to the ObjC runtime. The Info.plist uses
// $(PRODUCT_MODULE_NAME).FinderSync which Swift resolves to the same class.
@objc(FinderSync)
public final class FinderSync: FIFinderSync {

    private var templates: [Template] = []
    private var settings = Settings()
    private var namePanel: NamePanelController?

    private lazy var store: TemplateStore = {
        let builtin = Bundle.main.resourceURL?
            .appendingPathComponent("Templates", isDirectory: true)
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Templates", isDirectory: true)
        NFLog.info("builtin templates at \(builtin.path)")
        // Sandbox: Application Support resolves inside THIS extension's
        // private container, so the app could never share templates through
        // it. Use the app group container instead (shared with the app).
        let userRoot = TemplateStore.defaultUserRoot()
        NFLog.info("user templates at \(userRoot.path)")
        return TemplateStore(builtinRoot: builtin, userRoot: userRoot)
    }()

    override init() {
        super.init()
        NFLog.info("FinderSync extension initialized")

        // Claim everything: menu should appear in every folder, on the
        // desktop and on background right-clicks.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        NFLog.info("claimed directoryURLs = /")

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
        NFLog.info("settings reloaded: alwaysPrompt=\(settings.alwaysPrompt) neverPrompt=\(settings.neverPrompt) autoOpen=\(settings.autoOpen) disabled=\(settings.disabledIDs.count)")
        let result = store.load()
        templates = result.templates
        if !result.errors.isEmpty {
            NFLog.error("template load errors: \(result.errors.joined(separator: "; "))")
        }
    }

    // MARK: - NSExtensionRequestHandling

    /// Required by NSExtensionRequestHandling. Called when the extension is
    /// asked to handle a request from the host (Finder).
    public override func beginRequest(with context: NSExtensionContext) {
        NFLog.info("beginRequest with context \(context)")
    }

    // MARK: - Menu

    public override func menu(for menuKind: FIMenuKind) -> NSMenu {
        NFLog.info("menu(for: \(menuKind.rawValue)) called")
        let menu = NSMenu(title: "")

        let rootTitle = NSLocalizedString("menu.root", value: "New File", comment: "Root menu title")
        let rootItem = NSMenuItem(title: rootTitle, action: nil, keyEquivalent: "")
        rootItem.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)

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
                var item = NSMenuItem(
                    title: menuTitle(for: template),
                    action: #selector(createFromTemplate(_:)),
                    keyEquivalent: "")
                item.target = self
                // Finder dispatches the action on a *copy* of the menu item
                // it re-materializes from our returned menu. On macOS 26/27
                // that copy loses `representedObject` (it arrives as nil),
                // but `tag` survives. Keep both: tag is the primary key.
                item.tag = templates.firstIndex(where: { $0.id == template.id }) ?? -1
                item.representedObject = template.id
                item.keyEquivalent = "\r"
                item.keyEquivalentModifierMask = []
                if let icon = template.descriptor.icon,
                   let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
                    item.image = image
                } else {
                    // Fall back to a generic icon when the template's SF
                    // Symbol name doesn't exist on this macOS version.
                    item.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
                }
                submenu.addItem(item)

                // AppKit requires an alternate item to share the base item's key
                // equivalent, then differ only by modifier mask. Without that
                // pairing, Finder Sync renders all variants as normal rows.
                let alternate = item.copy() as! NSMenuItem
                alternate.title = menuTitle(
                    for: template,
                    modifiers: [.option]
                )
                alternate.isAlternate = true
                alternate.keyEquivalent = item.keyEquivalent
                alternate.keyEquivalentModifierMask = [.option]
                submenu.addItem(alternate)

                let instant = item.copy() as! NSMenuItem
                instant.title = menuTitle(
                    for: template,
                    modifiers: [.control]
                )
                instant.isAlternate = true
                instant.keyEquivalent = item.keyEquivalent
                instant.keyEquivalentModifierMask = [.control]
                submenu.addItem(instant)
            }

            // Modifier hint, like Finder's own alternative items.
            submenu.addItem(.separator())
            let hint = NSMenuItem(
                title: NSLocalizedString("menu.hint",
                    value: "Hold Option to rename, Control for instant create",
                    comment: "Modifier hint, disabled item"),
                action: nil, keyEquivalent: "")
            hint.isEnabled = false
            submenu.addItem(hint)
        }

        rootItem.submenu = submenu
        menu.addItem(rootItem)
        return menu
    }

    private func menuTitle(for template: Template) -> String {
        menuTitle(for: template, modifiers: NSEvent.modifierFlags)
    }

    private func menuTitle(for template: Template, modifiers: NSEvent.ModifierFlags) -> String {
        let name = template.localizedName()
        if shouldPrompt(for: template, modifiers: modifiers) {
            return String(format: NSLocalizedString("menu.item.prompt",
                value: "%@\u{2026}", comment: "Item that will ask for a name"), name)
        }
        return name
    }

    /// One source of truth for smart naming, used both to decorate the menu
    /// ("..." means this item will present a naming panel) and to dispatch
    /// the action. This prevents the icon and behavior from diverging.
    private func shouldPrompt(for template: Template, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch effectiveNamingPolicy(for: template, modifiers: modifiers) {
        case .prompt: return true
        case .silent: return false
        case .smart:  return template.usesFilenameAsData
        }
    }

    private func effectiveNamingPolicy(
        for template: Template,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) -> Settings.NamingPolicy {
        let flags = modifiers
        if flags.contains(.control) { return .silent }
        if flags.contains(.option) { return .prompt }
        return settings.namingPolicy
    }

    // MARK: - Action

    @objc private func createFromTemplate(_ sender: NSMenuItem) {
        let templateID = (sender.representedObject as? String)
            ?? (sender.tag >= 0 && sender.tag < templates.count ? templates[sender.tag].id : nil)
        NFLog.info("createFromTemplate: representedObject=\(sender.representedObject as? String ?? "nil") tag=\(sender.tag) resolved=\(templateID ?? "nil")")
        reloadState()   // pick up any template edits since the menu opened
        guard let templateID, let template = templates.first(where: { $0.id == templateID }) else {
            NFLog.error("template not found (tag=\(sender.tag), representedObject=\(sender.representedObject as? String ?? "nil"))")
            return
        }
        NFLog.info("found template \(template.id)")
        guard let directory = targetDirectory() else {
            NFLog.error("no target directory - targetedURL and selectedItemURLs both nil")
            NSSound.beep()
            return
        }
        NFLog.info("target directory \(directory.path)")

        if shouldPrompt(for: template, modifiers: NSEvent.modifierFlags) {
            NFLog.info("presenting name panel")
            presentNamePanel(for: template, in: directory)
        } else {
            NFLog.info("silent create")
            let base = FileCreator.defaultBaseName(for: template, directory: directory)
            create(template, baseName: base, in: directory)
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
        // NOTE on activation policy: FIFinderSync runs our selector on its
        // own XPC callback thread. NSApp.setActivationPolicy + window work
        // is not main-thread-safe there and FIFinderSync catches the
        // resulting NSException, silently swallowing our whole action
        // (we saw this as "caught an exception while executing selector").
        // Hop to the main thread for any UI work.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.presentNamePanel(for: template, in: directory) }
            return
        }
        // Inside a sandboxed appex NSApp starts with the .prohibited
        // activation policy: makeKeyAndOrderFront silently no-ops, so the
        // naming panel would never appear (and its completion would never
        // fire, which looks exactly like "the click did nothing"). Switching
        // to .accessory makes the window server actually show it.
        NSApp.setActivationPolicy(.accessory)
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
        // Same reason as in presentNamePanel: run on the main thread.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.create(template, baseName: baseName, in: directory) }
            return
        }
        NFLog.info("creating \(baseName) in \(directory.path)")
        do {
            // Make sure the host app is running so its Mach service is up.
            // openApplication(at:configuration:) is async; we only kick it
            // off here and rely on the placement call below for the real
            // work. No artificial sleep needed.
            if let appURL = hostAppURL() {
                NSWorkspace.shared.openApplication(at: appURL,
                                                   configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            }

            // Primary path: stage inside the sandbox container, then ask
            // the (unsandboxed) app to place the file. `autoOpen` is handled
            // by the app side - the sandboxed extension calling
            // NSWorkspace.open() would be blocked by TCC.
            let autoOpen = settings.autoOpen && template.descriptor.openAfterCreate
            if let url = try FinderPlacement.place(from: template,
                                                   baseName: baseName,
                                                   in: directory,
                                                   autoOpen: autoOpen) {
                NFLog.info("created at \(url.path)")
                return
            }
            // Fallback: direct write. Succeeds only if the extension already
            // holds security scope for the target (e.g. user granted access
            // in Preferences before).
            let url = try FileCreator.create(from: template, baseName: baseName, in: directory)
            NFLog.info("created at \(url.path)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            // An NSAlert cannot be presented from a sandboxed extension in
            // most cases, so the error log below is the primary signal:
            //   log show --last 5m --predicate 'subsystem == "com.newforge.app"'
            NFLog.error("create failed for \(baseName).\(template.fileExtension) in \(directory.path): \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    private func hostAppURL() -> URL? {
        // appex is at <app>/Contents/PlugIns/<ext>.appex
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "appex" else { return nil }
        return bundle.deletingLastPathComponent()   // PlugIns/
                     .deletingLastPathComponent()   // Contents/
                     .deletingLastPathComponent()   // <app>
    }
}
