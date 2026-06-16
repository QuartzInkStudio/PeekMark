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

## Cutting a Release

```bash
# 1. Confirm CFBundleShortVersionString and tag version match
# 2. Tag: git tag v1.0.0
# 3. Run release script:
./scripts/release.sh 1.0.0
```

## After the Script

1. Create GitHub Release for `v1.0.0`, upload `build/Release/sparkle/PeekMark-1.0.0.dmg`
2. Commit and push the generated `docs/appcast.xml`
3. Confirm `https://peekmark.app/appcast.xml` includes the new `<item>`
4. Announce on X/Twitter, 少数派, V2EX, Product Hunt (see README marketing notes)

## Sparkle Key Setup (one-time)

```bash
# Download Sparkle release, extract generate_keys tool
./generate_keys
# Save the PRIVATE key somewhere safe (NOT in the repo)
# Add the PUBLIC key to QuickMarkApp/Info.plist as SUPublicEDKey
```
