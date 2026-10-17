#!/bin/bash
# Generate NewForge.xcodeproj via XcodeGen (optional, requires `brew install xcodegen`).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "XcodeGen not found. Install with: brew install xcodegen" >&2
    exit 1
fi

xcodegen
echo "Generated NewForge.xcodeproj"
