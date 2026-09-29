# Browsair — PRD v0.3 (Login Reliability & Honest Product)

**Status:** Executing
**Date:** 2026-09-28
**Source:** Distilled from `docs/improvement-plan-2026-09.md` (audit).
**Method:** Test-driven development — each feature has a test that fails on `main`, then a minimal implementation to make it pass. UI-only behavior that can't run headless is covered by extracted pure logic + tests, and flagged as needing manual browser verification.

## Objective

Make "log into my email and stay logged in" actually work, and make the shipped
product honest: no dead weight, no broken privacy promise, no fabricated green.

## Scope decisions (locked)

- Delete the bundled Obscura/CDP engine from the default product.
- Lead with login reliability over new user-facing features.

## In scope (v0.3)

1. Engine removal (product size + false test failure).
2. A content blocker that actually blocks third-party trackers without breaking login hosts.
3. Popups/`window.open` become live, correctly-sized tabs.
4. No double navigation per command.
5. Per-site privacy allowlist so a login page can be un-blocked and reloaded.
6. A bounded sidebar web-view registry (no unbounded static growth).
7. Doc truth: superseded PRDs marked, duplicate page-text scrubber removed.

## Out of scope (deferred, listed for continuity)

- Developer ID signing + notarization (`Browsair.entitlements`) — needs a signing identity.
- Deleting `OAuthConnect.swift` borrowed-client-ID loopback flow — needs a product decision on OAuth.
- Cookie two-process regression test — needs a process-launch harness (see Open questions).
- Find-in-page, downloads, bookmarks/history, password autofill, zoom/fullscreen.
- Wiring or deleting `AgentBridge`.

## Success metrics

- `swift test` is green (was 91 tests / 1 failure).
- Shipped `.app` contains no Obscura binaries (was ~180 MB).
- Content-blocker ruleset: no rule uses `url-filter: ".*"` together with `if-domain`; login hosts are exempt; a third-party tracker is blocked.
- `createWebViewWith` returns a non-nil `WKWebView` and honors `windowFeatures` width/height.
- A single `navigate(...)` produces exactly one page load.
- No static collection in `Sources/` grows unbounded across tab churn.

## User stories

- As a user, typing `localhost:3000` or clicking a `target=_blank` login link opens a real, visible tab.
- As a privacy-conscious user, trackers are blocked, but turning privacy off for a site and reloading reaches that site.
- As a user, signing in does not reload the page twice or lose the popup.

## Functional requirements

### Content blocking (FR-1)
- Each blocked host emits a rule with a **host-specific** `url-filter` regex (RE2-lite: concatenation + char classes + `.*` suffix; **no alternation**), `if-domain: ["*host"]`, and `load-type: ["third-party"]`.
- `PrivacyPolicy.hostFilterRegex(_:)` must satisfy: a regex char in the host yields `nil` (skip, never emit an invalid rule); a valid host yields `^host` then escaped literal then `.*`.
- Login hosts in `protectedLoginHosts` are never emitted as blocked rules and are never blocked by the delegate matcher.
- The navigation delegate keeps `shouldBlock(url:firstPartyHost:)` as a secondary net for top-frame navigations.

### Popups (FR-2)
- `WebViewFactory.makePopupView` builds a `WKWebView` honoring `windowFeatures` size.
- `PopupSize.resolve(from:default:)` clamps to sane bounds (no zero/huge, no negative).
- `createWebViewWith` constructs the view, binds it to the new tab, registers it, and returns it (non-nil).

### Navigation (FR-3)
- `BrowserSession.consumePageCommand(for:)` atomically reads and clears the tab's pending command; `applyPageCommand` uses it so a command is applied at most once.

### Per-site privacy (FR-4)
- `PrivacyPolicy.isAllowed(host:)` / `allow(_:)` / `removeAllowed(_:)` / `allowedHosts` back a host allowlist; `shouldBlock` returns false for allowed hosts (with subdomain matching).

### Sidebar registry (FR-5)
- `WebViewRegistry` is bounded (FIFO eviction beyond `capacity`) and drops nil/empty entries; the sidebar reads page text through it.

## Acceptance criteria

- `swift build` and `swift test` succeed on macOS 14+.
- Every FR above has at least one unit test that was written to fail before the implementation.
- README storage-path claim corrected; `improvement-prd.md` marked superseded.

## Open questions / risks

- **Cookie persistence across relaunch (audit F3)** stays unverified this pass: it needs a two-process launch harness. Not fabricating a passing test for it.
- **UI-only paths** (popup actually rendering, find, downloads) can't be driven in this headless env; logic is tested via extracted pure functions and marked for manual browser verification.
- **Rule compilation proof** must run inside the app/UI-test target (`WKContentRuleListStore` never calls back in a CLI tool); here we test rule *shape* via `JSONDecoder` round-trip instead.
