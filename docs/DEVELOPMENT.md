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

### Ad-hoc signing caveat

macOS hides Finder extensions from unsigned/ad-hoc apps on some versions.
If the extension does not show up in the list:

1. Use `project.yml` + XcodeGen to build with your (free) Apple Developer
   team: set `DEVELOPMENT_TEAM` in `Config/Shared.xcconfig` or in Xcode's
   Signing tab, then run from Xcode once.
2. Or keep iterating on logic via `make test` — the template engine and
   file creation paths are fully covered without the extension host.

`pluginkit -m | grep -i newforge` shows whether the system sees the
extension after `open`-ing the app.

## Architecture notes

- **NewForgeKit** has no AppKit dependency except `NamePanelController`
  (guarded by `#if canImport(AppKit)`), so it stays testable headlessly.
- Templates are plain folders: `template.json` (leniently decoded) plus a
  content file. Loading never fails globally — per-template errors are
  collected and surfaced in Preferences.
- Settings live in `UserDefaults.standard`; the app posts a Darwin
  notification (`com.newforge.app.settingsChanged`) after saving, and the
  extension reloads before building its menu.
- Modifier keys are read in `menu(for:)` via `NSEvent.modifierFlags`:
  Option forces the naming panel, Control forces silent creation.

## Tests

`make test` compiles `Tests/NewForgeKitTests/main.swift` into a small
runner. XCTest is unavailable without full Xcode, so the harness is
hand-rolled (`check` / `expectEqual` / `expectThrows`).

## Roadmap ideas

- Per-template "auto-open" overrides in Preferences
- Template import/export (share a folder as a `.newforge-template` bundle)
- Context-aware ordering (suggest frontend templates inside npm projects)
