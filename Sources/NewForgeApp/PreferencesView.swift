import SwiftUI
import NewForgeKit

struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        TabView {
            templatesTab
                .tabItem { Label(NSLocalizedString("prefs.templates", value: "Templates", comment: ""),
                                 systemImage: "doc.on.doc") }
            generalTab
                .tabItem { Label(NSLocalizedString("prefs.general", value: "General", comment: ""),
                                 systemImage: "gear") }
            helpTab
                .tabItem { Label(NSLocalizedString("prefs.enable", value: "Enable in Finder", comment: ""),
                                 systemImage: "questionmark.circle") }
        }
        .padding(12)
        .onAppear {
            if model.showingEnableHelp {
                // Jump to the help tab when opened from the menu bar hint.
            }
        }
    }

    // MARK: Templates

    private var templatesTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("prefs.templates.subtitle",
                value: "Checked templates appear in the Finder \"New File\" menu.",
                comment: ""))
                .font(.callout)
                .foregroundColor(.secondary)

            List {
                ForEach(model.grouped(), id: \.group) { section in
                    Section(header: Text(model.groupTitle(section.group))) {
                        ForEach(section.items, id: \.id) { template in
                            TemplateRow(
                                template: template,
                                enabled: model.isEnabled(template),
                                origin: template.origin
                            ) { newValue in
                                model.setEnabled(template, newValue)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            if !model.loadErrors.isEmpty {
                Text(String(format:
                    NSLocalizedString("prefs.loadErrors", value: "%d template(s) failed to load. Check the Templates folder.", comment: ""),
                    model.loadErrors.count))
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            HStack {
                Button(NSLocalizedString("prefs.openFolder", value: "Open Templates Folder", comment: "")) {
                    let url = TemplateStore.defaultUserRoot()
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(url)
                }
                Spacer()
                Button(NSLocalizedString("prefs.reload", value: "Reload", comment: "")) {
                    model.reload()
                }
            }
        }
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Section(header: Text(NSLocalizedString("prefs.naming", value: "Naming", comment: ""))) {
                Picker("", selection: Binding(
                    get: { self.model.settings.namingPolicy },
                    set: { policy in
                        self.model.settings.alwaysPrompt = policy == .prompt
                        self.model.settings.neverPrompt = policy == .silent
                    }
                )) {
                    Text(NSLocalizedString("prefs.naming.smart", value: "Smart (recommended)", comment: ""))
                        .tag(Settings.NamingPolicy.smart)
                    Text(NSLocalizedString("prefs.naming.prompt", value: "Always ask", comment: ""))
                        .tag(Settings.NamingPolicy.prompt)
                    Text(NSLocalizedString("prefs.naming.silent", value: "Never ask", comment: ""))
                        .tag(Settings.NamingPolicy.silent)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if model.settings.namingPolicy == .smart {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(NSLocalizedString("prefs.naming.smartExplanation",
                                value: "Items whose contents or default name use the typed file name will ask for a name. Other items are created immediately.",
                                comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("prefs.naming.smartExample",
                                value: "Examples: Python Script asks for a name; Untitled Text creates without a dialog.",
                                comment: ""))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if model.settings.namingPolicy == .prompt {
                    Label(NSLocalizedString("prefs.naming.promptStatus",
                        value: "Every template will open the naming panel.",
                        comment: ""), systemImage: "pencil.and.list")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label(NSLocalizedString("prefs.naming.silentStatus",
                        value: "Every template is created immediately with its default name.",
                        comment: ""), systemImage: "bolt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(NSLocalizedString("prefs.naming.hint",
                    value: "In the Finder menu: hold Option to force the rename dialog, hold Control to create instantly.",
                    comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text(NSLocalizedString("prefs.behavior", value: "Behavior", comment: ""))) {
                Toggle(NSLocalizedString("prefs.autoOpen", value: "Open file after creation", comment: ""),
                       isOn: $model.settings.autoOpen)
            }

        }
        .formStyle(.grouped)
    }

    // MARK: Help

    private var helpTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("help.title", value: "Enable the Finder Extension", comment: ""))
                .font(.title2).bold()

            Label(NSLocalizedString("help.step1",
                value: "Open System Settings > Privacy & Security > Extensions > Finder Extensions (or Added Extensions).",
                comment: ""), systemImage: "1.circle")
            Label(NSLocalizedString("help.step2",
                value: "Check \"NewForge\" in the list.", comment: ""), systemImage: "2.circle")
            Label(NSLocalizedString("help.step3",
                value: "Right-click in any Finder window or on the Desktop: \"New File\" appears in the menu.",
                comment: ""), systemImage: "3.circle")

            Button(NSLocalizedString("help.openSettings", value: "Open Extensions Settings", comment: "")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.extensions?Finder") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Text(NSLocalizedString("help.note",
                value: "During development the extension is unsigned, so macOS may hide it until the app is built with a development team (see docs/DEVELOPMENT.md).",
                comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.top, 4)
    }
}

private struct TemplateRow: View {
    let template: Template
    let enabled: Bool
    let origin: String
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13))
                    .frame(width: 30, height: 30)
                Image(systemName: template.descriptor.icon ?? "doc")
                    .font(.system(size: 14, weight: .medium))
                    .imageScale(.medium)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(template.localizedName())
                Text(".\(template.fileExtension)")
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Toggle("", isOn: Binding(get: { enabled }, set: onToggle))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            if origin == "user" {
                Text(NSLocalizedString("prefs.badge.custom", value: "Custom", comment: ""))
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(4)
            }
        }
    }
}
