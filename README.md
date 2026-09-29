# Browsair

A Mac-native browser with SwiftUI chrome and a live WebKit page surface.

## Requirements

- macOS 14+
- Apple Silicon or Intel Mac
- Xcode / Swift 5.9+

## Quick start

```bash
swift test
swift run Browsair
```

## What it does

- Renders pages in a native, interactive WebKit view
- Blocks common advertising and analytics trackers by default
- Keeps an agent-friendly, local control contract without exposing a remote server
- Supports bounded structured DOM inspection for agents (selector, depth, and node limits)
- Optional AI sidebar with xAI/OpenAI-compatible provider support and Keychain-backed credentials
- Honest provider auth detection: no cookie scraping; official OAuth only when a provider documents and permits it
- Website data is managed by WebKit under `~/Library/WebKit/<bundle-id>/` and cookies under `~/Library/HTTPStorages/`

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
  Browser/    Tabs + session
  UI/         SwiftUI chrome + WKWebView surface
  Privacy/    Tracker blocking policy
  Agent/      In-process command contract
  AI/         Sidebar, Keychain, OAuth
```

## Limits (v0.3)

The visible UI uses WebKit. Extensions, password autofill, downloads, and history
restore are not built yet. The former headless Obscura/CDP engine has been removed
from the product (it was never started by the UI).
