# QuickMark

A lightweight macOS Markdown tool — Quick Look extension + menu bar viewer.

Press **Space** in Finder to preview any `.md` file with beautiful rendering.  
No subscription. No Electron. Native Swift, < 5 MB.

## Open Core

| Edition | License | How to get |
|---------|---------|-----------|
| **Community** (free) | AGPL-3.0 | Build from source or download signed binary |
| **Pro** (paid) | Proprietary | [quickmark.app](https://quickmark.app) — $9.99 one-time |

> The Community edition is fully open source. Pro modules are proprietary and
> distributed only in official signed binaries.

## Features (Community)

- ✅ Quick Look extension — render `.md` in Finder (Space bar)
- ✅ GitHub-flavored Markdown (GFM)
- ✅ Syntax highlighting (highlight.js)
- ✅ Auto light / dark mode
- ✅ System font (SF Pro + SF Mono)
- ✅ Zero remote requests — works offline

## Features (Pro)

- Custom CSS themes
- Mermaid diagram rendering
- LaTeX / KaTeX math
- PDF / DOCX export
- Menu bar scratchpad

## Build from Source

Requires macOS 14+, Xcode 15+.

```bash
git clone https://github.com/yourname/quickmark.git
cd quickmark
open QuickMark.xcodeproj
```

Build the `QuickMark` scheme. The Quick Look extension is included.

## License

Community edition: [AGPL-3.0](LICENSE)  
Pro modules: Proprietary — see [LICENSE-PRO](LICENSE-PRO)

### Contributing

By submitting a pull request you agree to the [Contributor License Agreement](CLA.md).
This allows the project to be dual-licensed (AGPL community + proprietary Pro).
