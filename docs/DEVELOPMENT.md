# Development

## Requirements

- macOS 14+
- **Build path A (default): Xcode Command Line Tools only** — the `Makefile`
  drives `swiftc` directly, no full Xcode install needed.
- Build path B (optional): full Xcode + XcodeGen (`brew install xcodegen`,
  then `./Scripts/gen-project.sh`) for debugging with breakpoints and proper
  asset-catalog compilation.

## Building

```bash
make            # -> build/NewForge.app
make run        # build + open
make test       # run NewForgeKit tests
```

The build is deliberately boring:

1. `Sources/NewForgeKit` compiles to a static archive + `.swiftmodule`.
2. The app and extension link against it.
3. `Resources/Templates`, `*.lproj` and `Assets.xcassets` are copied into
   the bundle verbatim.
4. Everything is ad-hoc codesigned (`codesign --sign -`).

## Running the extension locally

Finder Sync extensions are discovered through LaunchServices. After building:

```bash
open build/NewForge.app   # registers the .appex
./Scripts/enable-extension.sh --open-settings
```

Tick **NewForge** under System Settings → Privacy & Security → Extensions →
Finder Extensions, then right-click in Finder.

### Signing caveat (important)

macOS **Gatekeeper rejects ad-hoc signed app extensions** outright:
`spctl --assess --type execute <appex>` returns `rejected`, and the
extension never appears in `pluginkit -m -p com.apple.FinderSync` even
though LaunchServices registers the bundle. This is a hard security
policy, not a configuration issue.

To actually run the extension in Finder you must build with a (free)
Apple Developer team:

1. `brew install xcodegen && ./Scripts/gen-project.sh`
2. Open `NewForge.xcodeproj`, select the **NewForge** target → Signing &
   Capabilities → pick your Team (a free personal team works).
3. Do the same for **NewForgeFinderExt**.
4. Run the app once from Xcode, then enable it in Extensions settings.

The Makefile path is still useful for iterating on logic — `make test`
fully covers the template engine, file creation and naming panel without
needing the extension host.

### Debugging checklist

If the extension does not appear after signing with a team:

```bash
# Is the bundle registered with LaunchServices?
pluginkit -m -i com.newforge.app.finderext        # exit 0 = known

# Is it listed (elected) for the FinderSync point?
pluginkit -m -p com.apple.FinderSync | grep -i newforge

# Does Gatekeeper accept it?
spctl --assess --type execute -v \
  build/NewForge.app/Contents/PlugIns/NewForgeFinderExt.appex

# Is the entry point NSExtensionMain (not Swift's _main)?
nm .../NewForgeFinderExt | grep NSExtensionMain   # -> U _NSExtensionMain

# Re-register and relaunch
lsregister -f -R trusted "$PWD/build/NewForge.app"
open build/NewForge.app
```

Two build details the Makefile handles that are easy to get wrong by hand:

- `NSExtensionPrincipalClass` must be a literal `Module.Class` string;
  Xcode's `$(PRODUCT_MODULE_NAME)` variable is not expanded when you copy
  an Info.plist verbatim, so the Makefile substitutes real values.
- The extension binary must use `NSExtensionMain` as its entry point
  (`-Xlinker -e -Xlinker _NSExtensionMain`), which Foundation exports; it
  reads the principal class from the plist and hosts the XPC listener.

## Architecture notes

- **NewForgeKit** has no AppKit dependency except `NamePanelController`
  (guarded by `#if canImport(AppKit)`), so it stays testable headlessly.
- Templates are plain folders: `template.json` (leniently decoded) plus a
  content file. Loading never fails globally — per-template errors are
  collected and surfaced in Preferences.
- Settings live in the **shared app-group suite** (`group.com.newforge`),
  declared in both `*.entitlements` via `$(AppGroup)`. Sandboxed app and
  sandboxed extension each have a private defaults domain, so
  `UserDefaults.standard` would silently split settings in two. The app
  posts a Darwin notification (`com.newforge.app.settingsChanged`) after
  saving, and the extension reloads before building its menu.
- User templates live in the same group container
  (`TemplateStore.defaultUserRoot()`); the extension's own
  `~/Library/Application Support` resolves inside its private container
  and is never shared with the app.
- Modifier keys are read in `menu(for:)` via `NSEvent.modifierFlags`:
  Option forces the naming panel, Control forces silent creation.
- All diagnostic output goes through `os_log` with subsystem
  `com.newforge.app` (`NFLog` in NewForgeKit). `NSLog` output from
  sandboxed extensions is data-protected and invisible in `log show`,
  which used to make failures look like "the click did nothing".
  Inspect with:
  `log show --last 5m --predicate 'subsystem == "com.newforge.app"'`
- The naming panel is a plain `NSPanel`; inside an appex the activation
  policy starts as `.prohibited`, so `makeKeyAndOrderFront` no-ops. The
  extension switches to `.accessory` before showing the panel.
- File writes go through a **Mach service helper** (the main app):
  the extension stages the fully-rendered file inside its own container
  (`Library/Caches/com.newforge.staging`) and hands the path to
  `com.newforge.app.creation`. The app, which is deliberately *not*
  sandboxed, copies it into the requested folder and returns the final
  URL. This is how we get "any folder works after the app is running"
  without asking the user to grant per-folder access.

## Tests

`make test` compiles `Tests/NewForgeKitTests/main.swift` into a small
runner. XCTest is unavailable without full Xcode, so the harness is
hand-rolled (`check` / `expectEqual` / `expectThrows`).

## Roadmap ideas

- Per-template "auto-open" overrides in Preferences
- Template import/export (share a folder as a `.newforge-template` bundle)
- Context-aware ordering (suggest frontend templates inside npm projects)
