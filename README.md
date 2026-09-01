# Browsair

A Mac-native browser powered by [Obscura](https://github.com/h4ckf0r0day/obscura) — not WebKit, not Safari.

SwiftUI chrome (tabs, URL bar, navigation) talks to a bundled Obscura engine over the Chrome DevTools Protocol. Pages are painted by Obscura’s own Rust renderer and streamed into the window as screenshots.

## Requirements

- macOS 14+
- Apple Silicon or Intel Mac
- Xcode / Swift 5.9+
- Network access to download the Obscura engine once

## Quick start

```bash
./scripts/fetch-engine.sh   # downloads Obscura v0.2.1 (~90MB)
swift run Browsair
```

## What it does

- Launches `obscura serve` on a private localhost port
- Opens tabs as Obscura targets
- Navigates with `Page.navigate`
- Shows live frames via `Page.captureScreenshot`
- Forwards clicks, scroll, and keys through the CDP Input domain
- Persists cookies/localStorage under `~/Library/Application Support/Browsair`

## Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘T | New tab |
| ⌘W | Close tab |
| ⌘R | Reload |
| ⌘[ / ⌘] | Back / Forward |
| ⌘L | Focus address bar (notification) |

## Project layout

```
Sources/Browsair/
  Engine/     Obscura process + CDP client
  Browser/    Tabs + session
  UI/         SwiftUI chrome + page surface
Vendor/obscura/   Downloaded engine binary (gitignored)
```

## Attribution

Obscura is Apache-2.0. See [ATTRIBUTIONS.md](ATTRIBUTIONS.md).

Browsair is an independent project and is not affiliated with the Obscura authors.

## Limits (v1)

Obscura is an independent browser engine. Rendering fidelity is not Chrome/Safari-identical. The UI is screenshot-driven, so it will feel less snappy than a compositor-backed browser. Extensions, passwords, and downloads are not built yet.
