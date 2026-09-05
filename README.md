# Browsair

A Mac-native browser with SwiftUI chrome and a live WebKit page surface.

Obscura remains in-tree as an optional headless automation backend over the Chrome DevTools Protocol. It is not launched for interactive browsing and is not polled for screenshots.

## Requirements

- macOS 14+
- Apple Silicon or Intel Mac
- Xcode / Swift 5.9+

## Quick start

```bash
swift test
swift run Browsair
```

Headless Obscura is optional:

```bash
./scripts/fetch-engine.sh   # downloads Obscura v0.2.1 (~90MB)
```

## What it does

- Renders pages in a native, interactive WebKit view
- Blocks common advertising and analytics trackers by default
- Keeps an agent-friendly, local control contract without exposing a remote server
- Supports bounded structured DOM inspection for agents (selector, depth, and node limits)
- Optional AI sidebar with xAI/OpenAI-compatible provider support and Keychain-backed credentials
- Honest provider auth detection: no cookie scraping; official OAuth only when a provider documents and permits it
- Persists website data under `~/Library/Application Support/Browsair`

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
  Browser/    Tabs + session (no Obscura/CDP)
  UI/         SwiftUI chrome + WKWebView surface
  Privacy/    Tracker blocking policy
  Agent/      In-process command contract
  AI/         Sidebar, Keychain, OAuth
  Engine/     Optional headless Obscura + CDP (not started by the UI)
Vendor/obscura/   Downloaded engine binary (gitignored)
```

## Attribution

Obscura is Apache-2.0. See [ATTRIBUTIONS.md](ATTRIBUTIONS.md).

Browsair is an independent project and is not affiliated with the Obscura authors.

## Limits (v0.2)

The visible UI uses WebKit. Obscura is retained for future headless workflows and is not a drop-in replacement for WebKit’s compositor. Extensions, passwords, downloads, and remote CDP parity are not built yet.
