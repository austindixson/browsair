# Browsair Improvement PRD

**Status:** Proposed for v0.2
**Date:** 2026-09-01

## Summary

Browsair should be a fast, private, low-bloat Mac browser that works well with agents. The current prototype paints pages by polling Obscura screenshots over CDP. That transport is useful for headless capture, but it is not a good interactive browser surface: it introduces latency, makes text selection and scrolling fragile, and forces every input event through coordinate translation.

This improvement replaces screenshot painting with a native interactive WebKit surface while retaining Obscura as an optional headless/agent backend. Privacy blocking is enabled by default, and agent control is exposed through a small typed in-process bridge rather than a broad remote automation server.

## Goals

1. **Fast interaction:** native text selection, scrolling, links, forms, keyboard input, and page navigation.
2. **Private by default:** block known advertising and analytics resources, avoid telemetry, keep storage local, and do not expose a network control port.
3. **No bloat:** retain only tabs, navigation, address/search, privacy defaults, and useful agent controls.
4. **Agent-friendly:** provide deterministic state inspection and narrowly scoped commands for navigation, history, reload, and page inspection.
5. **Replaceable engine boundary:** keep headless Obscura integration isolated so the UI does not depend on screenshot transport.

## Non-goals

- Full Chrome or CDP parity.
- Extensions, password sync, accounts, downloads, or browser cloud services.
- Perfect tracker detection; the first release uses a bundled declarative rule set plus a conservative host policy.
- Exposing an HTTP/WebSocket automation endpoint to other machines.
- Preserving `Page.captureScreenshot` as the interactive rendering path.

## User stories

- As a user, I can open and use pages with native scrolling, selection, and form controls without waiting for screenshot refreshes.
- As a privacy-conscious user, common advertising and analytics requests are blocked without installing extensions.
- As a user, I can see that Browsair has no account, telemetry, or remote control service enabled.
- As an agent, I can inspect the active tab's URL, title, and loading state and issue validated navigation/history commands.
- As an agent, I can request narrowly scoped DOM text/state without receiving arbitrary local-file access or starting a remote listener.

## Functional requirements

### Rendering and navigation

- Render interactive pages in a native `WKWebView`.
- Preserve tabs, address normalization, title updates, loading state, history, and reload.
- Use the existing local Obscura process only for explicitly headless workflows; it must not be polled for UI screenshots.

### Privacy

- Install a `WKContentRuleList` before loading user pages.
- Block common third-party tracker, ad, pixel, and analytics host patterns.
- Allow first-party resources and malformed/non-HTTP URLs by default rather than breaking navigation.
- Store website data in Browsair's local app-support container; do not sync it.
- Keep any agent bridge in-process and local to the app.

### Agent bridge

- Commands are typed, JSON-decodable, and reject unknown commands or missing required fields.
- Minimum commands: `getState`, `navigate`, `reload`, `back`, `forward`, `readPageText`, and robust `inspect`.
- `inspect` accepts a CSS selector plus bounded depth/node/text options and returns a structured DOM snapshot with an explicit truncation flag.
- Inspection never returns `innerHTML`, script contents, form values, cookies, or arbitrary JavaScript results.
- Responses contain stable `ok`, `error`, and state/result fields.
- JavaScript evaluation is not a general-purpose escape hatch in v0.2; page text/state is the safe inspection primitive.

## Acceptance criteria

- `swift test` passes with coverage for URL normalization, tracker decisions, and agent command validation/encoding.
- A loaded page is a live native view; no `Page.captureScreenshot` polling or image-coordinate input mapping is used by the UI.
- Common analytics/ad hosts are blocked by the privacy policy, while a normal first-party page remains allowed.
- Agent commands cannot bind a port, access local files, or bypass URL validation.
- Navigation updates the active tab's URL/title/loading state.
- `swift build` succeeds on macOS 14+.

## Metrics

- No screenshot polling in the interactive path.
- Initial page surface appears without a periodic frame request.
- Native scroll and text selection work continuously.
- Privacy policy tests cover at least analytics, advertising, pixel, first-party, and malformed-host cases.
- Agent protocol tests cover valid commands, unknown commands, and invalid URLs.

## Architecture

`BrowserSession` owns tabs and navigation. `PageSurfaceView` hosts a `WKWebView` through a coordinator. `PrivacyPolicy` supplies testable host decisions and content-blocker JSON. `AgentCommand` and `AgentBridge` define the small in-process automation contract. `EngineProcess`/`CDPClient` remain available for future headless workflows but are not coupled to the visible page surface.

## Privacy and security

The app does not start a remote agent server. Agent calls must arrive through app-owned code. Private-network navigation remains disabled for Obscura, and the WebKit surface does not grant file URL access. Any future external agent transport requires a separate security review and explicit user opt-in.

## Rollout and follow-up

First ship the native surface and conservative blocking rules behind the existing browser shell. Then add a maintained rule-list update process, richer accessibility snapshots for agents, per-site privacy controls, and an optional reviewed external agent transport. If WebKit limitations become unacceptable, the surface can be replaced behind the same `BrowserSession` contract without reviving screenshot polling.
