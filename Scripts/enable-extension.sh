#!/bin/bash
# Print (and optionally open) everything needed to enable the Finder
# extension after a local build.
set -euo pipefail

APP="${1:-build/NewForge.app}"

cat <<EOF
NewForge built at: $APP

To enable the Finder extension:

  1. Launch the app once so LaunchServices registers the extension:
       open "$APP"

  2. Open the Extensions settings and tick "NewForge":
       System Settings > Privacy & Security > Extensions > Finder Extensions
     (on older macOS: System Preferences > Extensions > Finder)

  3. Right-click any Finder window background or the Desktop.
     You should see "New File" (or "新建文件") in the menu.

Note: ad-hoc signed (unsigned-team) builds are hidden by macOS unless you
build with a development team - see docs/DEVELOPMENT.md for details.
EOF

if [[ "${2:-}" == "--open-settings" ]]; then
    open "x-apple.systempreferences:com.apple.preference.extensions?Finder"
fi
