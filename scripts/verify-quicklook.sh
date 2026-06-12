#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: scripts/verify-quicklook.sh /path/to/QuickMark.app [/path/to/sample.md]" >&2
  exit 64
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 66
fi

SAMPLE_PATH="${2:-$(mktemp -t quickmark-quicklook.XXXXXX.md)}"
if [[ $# -lt 2 ]]; then
  printf '# QuickMark Quick Look Verification\n\nIf this renders, the extension is available.\n' > "$SAMPLE_PATH"
fi

APPEX_PATH="$APP_PATH/Contents/PlugIns/QuickMarkQL.appex"

echo "==> Checking app bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Checking Quick Look extension bundle"
if [[ ! -d "$APPEX_PATH" ]]; then
  echo "Quick Look extension missing: $APPEX_PATH" >&2
  exit 65
fi
/usr/bin/codesign --verify --strict --verbose=2 "$APPEX_PATH"

echo "==> Registering app with Launch Services"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$APP_PATH"

echo "==> Resetting Quick Look cache"
/usr/bin/qlmanage -r >/dev/null
/usr/bin/qlmanage -r cache >/dev/null

echo "==> Generating Quick Look preview for sample"
/usr/bin/qlmanage -p "$SAMPLE_PATH" >/dev/null 2>&1 &
QL_PID=$!
/bin/sleep 2
/bin/kill "$QL_PID" >/dev/null 2>&1 || true

echo "Quick Look verification launched successfully for: $SAMPLE_PATH"
echo "If the preview window rendered Markdown, Finder Space preview is ready."
