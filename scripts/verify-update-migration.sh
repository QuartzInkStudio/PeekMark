#!/usr/bin/env bash
# Exercise Sparkle feed resolution without launching or modifying either app.
# Usage: verify-update-migration.sh OLD.app NEW.app
set -euo pipefail
old_app="${1:?Pass the legacy signed app bundle}"
new_app="${2:?Pass the new app bundle}"
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
framework_dir="${SPARKLE_FRAMEWORK_DIR:-/opt/homebrew/Caskroom/sparkle/2.9.3}"
[[ -d "$framework_dir/Sparkle.framework" ]] || { echo "Sparkle.framework not found in $framework_dir" >&2; exit 1; }
old_app="$(cd "$old_app" && pwd)"
new_app="$(cd "$new_app" && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/peekmark-update-test.XXXXXX")"
suite="app.peekmark.update-test.$(uuidgen)"
trap 'defaults delete "$suite" >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Host.app/Contents"
python3 - "$new_app/Contents/Info.plist" "$tmp/Host.app/Contents/Info.plist" "$suite" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    info = plistlib.load(f)
info['CFBundleIdentifier'] = sys.argv[3]
info.pop('SUDefaultsDomain', None)
with open(sys.argv[2], 'wb') as f:
    plistlib.dump(info, f)
PY
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
import Sparkle

@MainActor func run() throws {
    guard CommandLine.arguments.count == 5,
          let old = Bundle(path: CommandLine.arguments[1]),
          let new = Bundle(path: CommandLine.arguments[2]),
          let isolated = Bundle(path: CommandLine.arguments[3]) else {
        fatalError("Could not open app bundles")
    }
    let suite = CommandLine.arguments[4]
    guard isolated.bundleIdentifier == suite,
          let defaults = UserDefaults(suiteName: suite) else { fatalError("Invalid isolated defaults suite") }
    defer {
        defaults.removePersistentDomain(forName: suite)
        defaults.synchronize()
    }
    let legacyURL = "https://peekmark.app/appcast.xml"
    guard old.bundleIdentifier == "app.peekmark.PeekMark",
          old.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "1",
          old.object(forInfoDictionaryKey: "SUFeedURL") as? String == legacyURL else {
        fatalError("Legacy bundle identity or feed differs from expected")
    }
    guard let expected = new.object(forInfoDictionaryKey: "SUFeedURL") as? String,
          expected != legacyURL, expected.hasPrefix("https://") else {
        fatalError("New bundle does not specify an isolated HTTPS feed")
    }
    func updater(_ host: Bundle, _ delegate: SPUUpdaterDelegate?) -> SPUUpdater {
        let driver = SPUStandardUserDriver(hostBundle: host, delegate: nil)
        return SPUUpdater(hostBundle: host, applicationBundle: host, userDriver: driver, delegate: delegate)
    }
    let legacyUpdater = updater(old, nil)
    guard legacyUpdater.feedURL?.absoluteString == legacyURL else {
        fatalError("Legacy Sparkle feed differs; check for an existing SUFeedURL preference override")
    }
    let delegate = UpdaterFeedDelegate()
    let newUpdater = updater(new, delegate)
    guard newUpdater.feedURL?.absoluteString == expected else { fatalError("New bundle feed resolution failed") }
    defaults.set(legacyURL, forKey: "SUFeedURL")
    defaults.synchronize()
    let unprotected = updater(isolated, nil)
    guard unprotected.feedURL?.absoluteString == legacyURL else { fatalError("Failed to reproduce stale preference override") }
    let protected = updater(isolated, delegate)
    guard protected.feedURL?.absoluteString == expected else { fatalError("Delegate failed to override stale preference") }
    print("Legacy Sparkle feed: \(legacyURL)")
    print("New Sparkle feed: \(expected)")
    print("PASS: stale preference overrides Info.plist without a delegate and is overridden by UpdaterFeedDelegate")
    print("Temporary bundle and preference suite were isolated; no update was downloaded or installed.")
}
try MainActor.assumeIsolated { try run() }
SWIFT
runtime_framework_dir="$old_app/Contents/Frameworks"
[[ -d "$runtime_framework_dir/Sparkle.framework" ]] || { echo "Legacy app has no Sparkle.framework" >&2; exit 1; }
swiftc -F "$framework_dir" -framework Sparkle -Xlinker -rpath -Xlinker "$runtime_framework_dir" \
  "$project_dir/QuickMarkApp/Sources/UpdaterSetup.swift" "$tmp/main.swift" -o "$tmp/probe"
"$tmp/probe" "$old_app" "$new_app" "$tmp/Host.app" "$suite"
