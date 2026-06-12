# Release Runbook

## Prerequisites

1. Apple Developer Program membership ($99/yr)
2. Developer ID Application certificate in Keychain
3. Sparkle EdDSA private key (generate once with `generate_keys` from Sparkle)
4. Environment variables set (add to `~/.zshrc` or pass inline):
   ```bash
   export APPLE_ID="you@example.com"
   export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # app-specific password from appleid.apple.com
   export TEAM_ID="XXXXXXXXXX"                 # 10-char team ID from developer.apple.com
   export SPARKLE_KEY_PATH="$HOME/.sparkle/private_key"
   ```

## Cutting a Release

```bash
# 1. Bump version in project.yml and Info.plist
# 2. Commit: git commit -am "chore: bump version to 0.x.0"
# 3. Tag: git tag v0.x.0
# 4. Run release script:
./scripts/release.sh 0.x.0
```

## After the Script

1. Create GitHub Release for `v0.x.0`, upload `build/PeekMark-0.x.0.dmg`
2. Update `appcast.xml` on your website with:
   - New `<item>` entry
   - `sparkle:edSignature` from the script output
   - `url` pointing to the GitHub Release asset
3. Announce on X/Twitter, 少数派, V2EX, Product Hunt (see README marketing notes)

## Sparkle Key Setup (one-time)

```bash
# Download Sparkle release, extract generate_keys tool
./generate_keys
# Save the PRIVATE key somewhere safe (NOT in the repo)
# Add the PUBLIC key to QuickMarkApp/Info.plist as SUPublicEDKey
```
