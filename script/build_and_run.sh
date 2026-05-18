#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${TMPDIR:-/tmp}/TimeMachinePlusPlusRunData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/TimeMachine++.app"

cd "$ROOT_DIR"

xcodebuild \
  -project TimeMachinePlusPlus.xcodeproj \
  -scheme TimeMachinePlusPlus \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

open "$APP_PATH"
