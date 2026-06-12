# PeekMark Pro Architecture

PeekMark uses an open-core model:

- **Community**: AGPL-3.0, fully public in this repository.
- **Pro**: proprietary, distributed only in official signed binaries.

## Repository Layout

Use two Git repositories, not one public folder:

```text
peekmark/                 # public AGPL repo
  QuickMarkApp/
  QuickMarkCore/
  QuickMarkQL/
  docs/
  project.yml

PeekMark-pro-kit/         # private repo
  Package.swift
  Sources/QuickMarkProKit/
    ProFeatureRegistry.swift
    ThemeEngine/
    MermaidRenderer/
    MathRenderer/
    Exporters/
    Licensing/
```

Do **not** put Pro implementation files in the public repository, even under an ignored folder, because it is too easy to accidentally commit them later.

## Public Repository Responsibilities

The public repo should contain:

- Community app, editor, preview, Quick Look extension.
- Shared renderer and stable extension points.
- Public docs explaining that Pro modules are proprietary.
- Optional compile-time hooks that are inert without Pro.

The public repo must not contain:

- License validation secrets.
- StoreKit/App Store Connect keys.
- Pro feature implementation.
- Private package URLs with embedded tokens.
- Sparkle private keys or release credentials.

## Private Pro Package Responsibilities

The private `QuickMarkProKit` should contain:

- Custom CSS theme engine.
- Mermaid rendering.
- KaTeX/LaTeX rendering.
- PDF/DOCX export.
- License activation and validation.
- Any paid-feature UI panels.

## Integration Pattern

Community defines a small protocol surface. Pro implements it privately.

Example public contract:

```swift
public protocol QuickMarkFeatureProvider {
    var displayName: String { get }
    func transformHTML(_ html: String, context: RenderContext) async throws -> String
}
```

Community build:

```swift
let providers: [QuickMarkFeatureProvider] = []
```

Official Pro build:

```swift
import QuickMarkProKit

let providers: [QuickMarkFeatureProvider] = QuickMarkProRegistry.providers
```

Keep the public contract small. Avoid leaking Pro class names, license server URLs, product IDs, or implementation details into Community code.

## Build Strategy

Use a private build overlay for official releases:

```text
peekmark-private-build/
  PeekMark-Pro.xcconfig
  project-pro.yml
  Package.resolved
  scripts/release-pro.sh
```

The private overlay adds:

- The private Swift Package dependency: `QuickMarkProKit` from `PeekMark-pro-kit`.
- `PRO` Swift compilation condition.
- Product bundle/signing/release settings.
- StoreKit product IDs or license endpoint config from local secrets.

The public repo remains buildable without access to Pro.

## Local Development Flow

Recommended local checkout:

```text
~/dev/peekmark/            # public repo
~/dev/PeekMark-pro-kit/    # private repo
~/dev/peekmark-build/      # private overlay/release scripts
```

During Pro development, the private overlay references `../PeekMark-pro-kit` as a local package. CI/release can reference the private Git URL using GitHub Actions secrets or a deploy key.

## Licensing Flow

Do not put license secrets in the app binary when avoidable.

Recommended options:

1. **Website license server** for direct sales.
   - App sends license key + machine fingerprint.
   - Server returns signed entitlement payload.
   - App verifies signature using a public key embedded in Pro.

2. **StoreKit 2** for App Store distribution later.
   - Separate build flavor.
   - Product IDs live in private config.

For GitHub-first distribution, start with direct-sale license keys and signed offline entitlements.

## CI and Secrets

Public CI should only build Community unsigned or ad-hoc signed.

Private release CI may use secrets:

- `APPLE_ID`
- `APP_PASSWORD` or notarytool keychain profile
- `TEAM_ID`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY` (`.p8` contents)
- `SPARKLE_PRIVATE_KEY`
- license server signing credentials

Never store these in the public repo.

## Decision

Use a **separate private Git repository** for Pro implementation, plus an optional private build-overlay repository for official releases.

Avoid a local-only `Pro/` folder inside this public repository. It works temporarily, but it increases accidental leak risk and makes CI/release boundaries unclear.
