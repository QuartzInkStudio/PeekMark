# Release Runbook

## Prerequisites

1. Apple Developer Program membership ($99/yr)
2. Developer ID Application certificate in Keychain
3. Sparkle EdDSA private key (generate once with `generate_keys` from Sparkle)
4. Environment variables set (add to `~/.zshrc` or pass inline):
   ```bash
   export TEAM_ID="XXXXXXXXXX"
   export NOTARY_PROFILE="your-keychain-profile"
   export SPARKLE_KEY_PATH="$HOME/.sparkle/peekmark_ed25519_private_key"
   export SPARKLE_SIGN_UPDATE_BIN="/opt/homebrew/Caskroom/sparkle/2.9.3/bin/sign_update"
   export SPARKLE_GENERATE_APPCAST_BIN="/opt/homebrew/Caskroom/sparkle/2.9.3/bin/generate_appcast"
   ```

## Publishing Community

1. Update the app and Quick Look extension version and build numbers, then
   build and test Community. Check Finder Quick Look and linked Markdown files.
2. Run `./scripts/release.sh <version>` to sign, notarize, and package the DMG.
3. Tag the tested source and publish a GitHub Release with
   `build/releases/<version>/sparkle/PeekMark-<version>.dmg`. Record its SHA-256 and
   update the Homebrew cask version, checksum, and homepage.
4. Commit the generated `docs/community/appcast.xml`. Copy it to
   `public/community/appcast.xml` in the standalone `peekmark-web` project
   and deploy that project to Cloudflare Pages.
5. Verify the live Community appcast and download. Confirm the Direct feed
   and the legacy appcast still serve their respective content.

The standalone Cloudflare Pages deployment serves the live appcasts.
Pushing changes to the app repository updates the source copy. Publish
the matching file through the website deployment to update the live feed.

## Sparkle Key Setup (one-time)

```bash
# Download Sparkle release, extract generate_keys tool
./generate_keys
# Save the PRIVATE key somewhere safe (NOT in the repo)
# Add the PUBLIC key to QuickMarkApp/Info.plist as SUPublicEDKey
```

## Edition update migration

The original Community and Direct 1.0.0 builds share the same bundle identifier,
version, Sparkle signing key and feed. The server cannot reliably identify their
edition. Keep `docs/appcast.xml` byte-for-byte frozen at its existing 1.0.0 item.
The release script and CI verify its SHA-256 before allowing new release work.

New Community builds use `https://peekmark.app/community/appcast.xml`.
New Direct builds use `https://peekmark.app/direct/appcast.xml`.
Both feeds start empty until a signed, notarized artifact is published for that
edition. Publish the feeds before distributing the new binaries. A stored
legacy feed preference is overridden by the installed app's updater delegate.

Legacy users migrate manually by quitting PeekMark and replacing their installed
app with the new package for their edition. Direct customers must use the Direct
package. Keep the original bundle identifier, Developer ID team, signing
requirement and Keychain service/account so existing licenses remain accessible.
Community users use the Community package. Future updates follow the new feed.
The legacy shared feed stays frozen even after some users migrate.

Before publishing an edition, run:

```bash
python3 scripts/verify-update-feeds.py --app /path/to/new/PeekMark.app --edition community
scripts/verify-update-migration.sh /path/to/old/PeekMark.app /path/to/new/PeekMark.app
```

Use `--edition direct` for a Direct artifact. The migration probe loads the old
app's Sparkle framework and tests actual feed selection with the new updater
delegate, including a stale preference in an isolated temporary preferences
suite. It does not install an update or activate a license.

Release acceptance also requires a signed and notarized Direct installer,
replacement of an old licensed installation, relaunch, and confirmation that
its Pro entitlement and documents remain accessible. Check updates in the new
app and confirm it requests the Direct feed. Record this separately from the
feed-resolution probe. Never publish a newer Community item to the legacy feed.

### Verification on 2026-11-14

Community Debug and Direct Debug builds passed. Direct 1.0.1 build 2 archived
and exported with Developer ID signing and passed deep signature verification.
The old and new Direct signing requirements, bundle identifiers, entitlements,
and Sparkle public keys matched. The migration probe passed for both editions
using each old app's embedded Sparkle framework. Negative checks rejected a
changed legacy feed and a feed with the wrong channel URL. The live legacy feed
matched the frozen SHA-256 above.

The Community and Direct feeds first went live on GitHub Pages from commit
`c307bb5`. Both returned HTTP 200 and matched the staged standalone site's feeds.
The legacy feed still matches the frozen SHA-256. Apple accepted the Direct
1.0.1 build 2 app and DMG. Stapled tickets, deep app signature, and Gatekeeper
checks passed.

The activated Direct 1.0.0 build 1 opened the QuickMark workspace in the
test installation. Replacing it with the notarized Direct 1.0.1 build 2
preserved Pro activation and reopened the same workspace and document list.
A live check using the installed Sparkle framework loaded the Direct feed
and reported that the app was up to date. The test used an existing local
license.

The standalone site is live at `https://peekmark.app/` on Cloudflare Pages.
The published Direct 1.0.1 DMG matches the notarized local artifact. All three
appcast responses matched the pre-cutover files byte for byte, and the six
Playground routes returned HTTP 200. The purchase button goes through the
existing license gateway to Dodo Live. The deployed return page points
verified buyers to the standalone download. Checkout was verified up to
the Dodo redirect and the incomplete-return response.

Community 1.0.1 build 2 passed notarization and Finder Quick Look verification.
The installed Community extension rendered the Markdown heading, table, and
local link. Its release signature includes App Sandbox and the same WebKit
network client entitlement used by the Mac App Store extension.

Direct 1.0.2 build 3 fixes Finder Quick Look registration and WebKit rendering
with the extension entitlements verified in Community 1.0.1. Apple notarized
the app and DMG. A replacement of the activated Direct 1.0.1 QA installation
preserved Pro and reopened its workspace. Finder Space rendered a Markdown
heading, table, and local link, with the process traced to the Direct 1.0.2
extension. The live Direct appcast offers build 3 to 1.0.1 and reports no
newer version to 1.0.2. Its enclosure signature verifies with the public key
embedded in Direct 1.0.1. The website and checkout use the stable
`/downloads/PeekMark-Direct.dmg` link. Deploy the versioned DMG and update the
stable redirect and Direct feed together for future website releases.
