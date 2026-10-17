import Foundation
import NewForgeKit

/// View model bridging the template store / settings store to SwiftUI.
final class PreferencesModel: ObservableObject {
    @Published var templates: [Template] = []
    @Published var settings = Settings() {
        didSet { SettingsStore.save(settings) }
    }
    @Published var loadErrors: [String] = []
    @Published var showingEnableHelp = false

    private let store: TemplateStore

    init() {
        let builtin = Bundle.main.resourceURL?
            .appendingPathComponent("Templates", isDirectory: true)
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Templates", isDirectory: true)
        store = TemplateStore(builtinRoot: builtin, userRoot: TemplateStore.defaultUserRoot())
        settings = SettingsStore.load()
        reload()
    }

    func reload() {
        let result = store.load()
        templates = result.templates
        loadErrors = result.errors
    }

    func isEnabled(_ template: Template) -> Bool {
        !settings.disabledIDs.contains(template.id)
    }

    func setEnabled(_ template: Template, _ enabled: Bool) {
        if enabled {
            settings.disabledIDs.remove(template.id)
        } else {
            settings.disabledIDs.insert(template.id)
        }
    }

    func grouped() -> [(group: String, items: [Template])] {
        let order = ["office", "analysis", "dev", "web", "misc", "other"]
        let dict = Dictionary(grouping: templates, by: { $0.descriptor.group })
        return order.compactMap { key in
            guard let items = dict[key], !items.isEmpty else { return nil }
            return (key, items)
        }
    }

    func groupTitle(_ group: String) -> String {
        switch group {
        case "office": return NSLocalizedString("group.office", value: "Office", comment: "")
        case "analysis": return NSLocalizedString("group.analysis", value: "Data Analysis", comment: "")
        case "dev": return NSLocalizedString("group.dev", value: "Development", comment: "")
        case "web": return NSLocalizedString("group.web", value: "Web", comment: "")
        case "misc": return NSLocalizedString("group.misc", value: "Miscellaneous", comment: "")
        default: return NSLocalizedString("group.other", value: "Other", comment: "")
        }
    }
}
