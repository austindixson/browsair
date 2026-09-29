# Browsair — Audit & Improvement Plan (v0.3)

**Status:** Active plan
**Date:** 2026-09-28
**Supersedes:** `docs/browser-parity-plan.md` (2026-09-27) for execution order; that doc remains useful as the root-cause narrative.
**Baseline:** `swift build` OK. `swift test` → 91 tests, **1 failing** (`ObscuraEngineTests.testHeadlessSessionNavigatesAndEvaluates`).
**Decisions this plan commits to:**
- Login reliability is the lead priority.
- The bundled Obscura/CDP engine is **deleted from the default product** (kept available as an opt-in separate target, not shipped in the browsing app).

---

## 1. What changed since the 2026-09-27 audit

Several previously-planned PRs have already landed and are covered by tests:

- **PR 1.2 (popups):** `UI/WebKitUIDelegate.swift` now implements `WKUIDelegate` — `window.open` / `target=_blank` become a visible tab, and `alert`/`confirm` are no longer swallowed. `PopupHandlingTests` (6 tests) pin the decision + session wiring.
- **PR 1.3 (URL classifier):** `Browser/URLClassifier.swift` replaces the old `contains(".")` heuristic. `URLClassifierTests` (18 tests) cover `localhost`, `.local`, IPv4 octets, bogus ports, fragments, relative paths, query-only strings, and `mailto:`/`tel:` passthrough. **F2 is genuinely fixed.**
- **PR 2.2 (partial):** `UI/PageSurfaceError.swift` maps provisional/certificate/unreachable errors to actionable strings and handles `webViewWebContentProcessDidTerminate`. `WebsiteDataStoreTests` (5 tests) cover the messages.
- **PR 3.3 (partial):** the AI sidebar now reads live page text (`PageTextExtractor.sanitize` + `AIContextPolicy.make`), so the model is no longer promised context that was never supplied. The `messages.last!` force-unwrap is gone (`?? text`).

What is **still open** is below.

---

## 2. Audit findings (current tree)

### P0 — correctness of the thing users actually do

**F1 — Tracker blocking does not actually work in WebKit.** (`Privacy/PrivacyPolicy.swift:79-95`, `UI/PageSurfaceView.swift:143-156`)
Two independent reasons, both verified against the shipped code:
1. Every rule is emitted as `url-filter: ".*"` with `if-domain: ["*<host>"]`. Apple's documented behavior: *"The `url-filter` … cannot be `.*` when `if-domain` or `unless-domain` are present."* WebKit rejects/ignores that combination, so the declarative ruleset is effectively inert as a blocker.
2. The first-party-aware Swift matcher `shouldBlock(url:firstPartyHost:)` is only invoked from `decidePolicyFor navigationAction` — which fires for **top-frame navigations only**. Third-party sub-resources (scripts, pixels, iframes: where every tracker lives) are decided by the declarative ruleset, which per (1) does nothing.

Net effect today: privacy blocking is mostly cosmetic, while the `protectedLoginHosts` exemption makes it *look* deliberate. The fix is to give each rule a real host `url-filter` regex (RE2-lite: concatenation + char classes + `.*` suffix, no alternation) with `load-type: ["third-party"]`, and keep the navigation-delegate matcher as a secondary net for top-frame cases.

**F2 — Popup web views are created then leaked.** (`UI/WebKitUIDelegate.swift:36-49`)
`webView(_:createWebViewWith:for:windowFeatures:)` calls `session.openPopup(...)` (which makes a *model* tab) but binds `var popup: WKWebView?` that **stays nil** and returns nil. WebKit therefore never receives a web view for the request; the tab later renders via a *separately constructed* `WKWebView` in `makeNSView`. Consequences: the returned view is discarded, `windowFeatures` (width/height/scrollbars) are ignored, and bare `window.open()` (URL assigned later) has no object to write to. `PopupHandlingTests` only exercise the pure `windowPolicy` decision — **no test runs the real delegate method**.

**F3 — Login cookies across relaunch remain unproven.** (`UI/PageSurfaceError.swift:37-62`, `Tests/…/WebsiteDataStoreTests.swift`)
`makePersistentStore()` simply returns `.default()`; no `WKWebsiteDataStoreConfiguration` is ever built, and the existing tests only assert that the *path string* is stable — never that a cookie written in process A is visible in process B. On top of that, the bundle identifier (what WebKit keys cookie storage on) comes from the `__TEXT,__info_plist` linker section, which is **not a code signature and is not visible to LaunchServices**; the `browsair://` OAuth callback scheme therefore will not route to a `swift run` binary. The README's claim that data persists under `~/Library/Application Support/Browsair` is still false.

**F4 — Every navigation can double-load.** (`Browser/BrowserSession.swift:126-136` + `UI/PageSurfaceView.swift:58-65,105-115`)
`navigate()` sets `tab.pageCommand = .load(url)`; the web view also rewrites `tab.urlString` in `didFinish`; because `updateNSView` runs on any `@Published` change and `applyPageCommand()` fires unconditionally, the same URL can be loaded twice. Wasted loads + flicker; the `lastLoadedURL` guard in `loadCurrentURL()` does not cover the `.load` command path.

### P1 — shipability

**F5 — ~180 MB dead engine ships in the product.** `Package.swift` still declares `.copy("Resources/Engine")`; `Resources/Engine/obscura` (94 MB) + `obscura-worker` (86 MB) are copied into the `.app` by `scripts/package-dmg.sh`. Nothing in `Sources/UI/` or `Sources/Browser/` starts the engine.

**F6 — The only failing test is the dead engine, and it's a false failure.** `ObscuraEngineTests.swift:59` asserts example.com's body text contains `"documentation examples"` or `"illustrative examples"`. The real page says *"designed to be illustrative"* — neither literal is present, so the assertion can never pass. This is a stale string check, not a product regression, but it keeps `swift test` permanently red and would block CI.

**F7 — Distribution is unsafe.** `Resources/Info.plist` sets `NSAllowsArbitraryLoads = true` app-wide; there is **no `.entitlements` file**; `package-dmg.sh` only ad-hoc-signs (`codesign -dvv` → `Signature=adhoc`, `TeamIdentifier=not set`) and hardcodes `Browsair-0.2.0.dmg`. Ad-hoc signatures change on every rebuild, so Keychain ACLs for service `com.browsair.ai` break between builds (R4 in the prior audit).

**F8 — The agent surface is dead code.** `Agent/AgentBridge.swift execute(...)` has **zero callers** in `Sources/`. It is only assigned a web view (`PageSurfaceView.swift:52,62`) and exercised from `AgentRuntimeTests`. The promised local control contract (PR 3.2) does not exist; there is no transport.

**F9 — Two divergent AI auth stacks + a borrowed client ID.** `AI/AIAuth.swift` + `AI/OAuthConnect.swift` coexist with `AI/OAuthAccounts.swift`. `OAuthConnect.swift:33` hardcodes Grok CLI's OAuth client ID (`b1a00492-…`) and `:93-101` starts a loopback `NWListener` — a ToS/credential-scoping problem for a third-party app. Separately, `PageTextExtractor.sanitize` and `AIContextPolicy.sanitize` are two overlapping regex scrubbers both applied to page text.

### P2 — gaps vs. a usable browser + repo hygiene

**F10 — Missing affordances** (grep-confirmed absent from `Sources/`, excluding the dead engine): find-in-page, downloads, bookmarks, history/restore-on-launch, zoom, fullscreen, password autofill, per-site privacy toggle.

**F11 — Unbounded global webview cache.** `AISidebarView.webViewCache: [ObjectIdentifier: WKWebView]` is a static dict written on every `didFinish` with **no eviction** — it grows for the life of the process and is never checked for liveness.

**F12 — No CI, no formatter/linter config; `docs/improvement-prd.md` is stale** (still says "Proposed for v0.2", superseded but unmarked).

---

## 3. Improvement plan — PRs with acceptance criteria

Each PR is independently shippable and testable. Login reliability = PRs 0.1, 1.1-1.4.

### Phase 0 — Make the truth green and the product honest

| PR | Change | Acceptance |
|---|---|---|
| **0.1** Delete engine from default product | Remove `.copy("Resources/Engine")` + Engine `.gitkeep`/icon excludes from `Package.swift`; delete `Sources/Browsair/Resources/Engine/*` binaries, `Vendor/`, `scripts/fetch-engine.sh`, and `Engine/` (`EngineProcess`, `CDPClient`, `CDPTypes`, `HeadlessSession`) + `EngineIsolationTests`, `ObscuraEngineTests`, `CDPTypesTests`; update `package-dmg.sh` (it currently also writes back `AppIcon.png/.icns` into `Sources/` — stop that side effect) and `README.md` | `swift build` + `swift test` green; `ls` shows no bundled binaries; DMG contains no engine; grep `obscura|CDP` hits docs only |
| **0.1b** (optional) Opt-in engine target | If headless capture is still wanted, move Obscura behind a separate `BrowsairHeadless` executable target with its own fetch script, excluded from the app product and from the default test run | `swift test` does not run engine tests by default; app target has no engine dependency |
| **0.2** Split `Info.plist` | `AppInfo.plist` (identity, `browsair://` scheme, icon, no ATS exception) and `AppInfo.debug.plist` (keeps `NSAllowsArbitraryLoads` for `http://localhost`); wire via the existing `-sectcreate` | A release build's embedded plist has **no** `NSAllowsArbitraryLoads`; debug build still allows `http://localhost` |
| **0.3** Scrub + document | Mark `docs/improvement-prd.md` superseded; delete one of the two overlapping page-text scrubbers (keep `PageTextExtractor`); add `.swiftlint.yml`/`swift-format` config and a CI workflow (build + `swift test`) | CI runs on push; `swift test` green in CI |

### Phase 1 — Login reliability (the headline goal)

| PR | Change | Acceptance |
|---|---|---|
| **1.1** Real declarative blocker | Emit per-host `url-filter` regexes (RE2-lite: no alternation) with `load-type: ["third-party"]`, drop the `.*`+`if-domain` shape and the `ads.`/`ad.`/`pixel.`/`analytics.` prefix hacks from the JSON; keep navigation-delegate `shouldBlock` as secondary net; surface compile errors through `PrivacyPolicy.lastBuildError` into `engineStatus`/UI | Test: ruleset contains no `url-filter:".*"` with `if-domain`; first-party docs for google.com, microsoftonline.com, github.com, appleid.apple.com, fastmail.com, protonmail.com are **not** blocked; a third-party `google-analytics.com` sub-resource **is** blocked |
| **1.2** Fix popup web-view lifecycle | Implement `createWebViewWith` to actually construct and return a `WKWebView` bound to the new tab (honoring `windowFeatures` for size), or explicitly reject returning nil; add an integration test that drives the **real delegate method**, not just `windowPolicy` | Test: a page calling `window.open(url)` yields a live, loaded tab; popup size respected; bare `window.open()` attaches |
| **1.3** Prove cookie persistence | Construct `WKWebsiteDataStore` from an explicit `WKWebsiteDataStoreConfiguration` (or document why `.default()` suffices) and add a **two-process regression test**: set a cookie in process A, terminate, relaunch, assert it's present; must fail on `main`, pass after | Two-process test goes red→green; README storage-path claim corrected to `~/Library/WebKit/<bundle-id>/` + `~/Library/HTTPStorages/` |
| **1.4** Stop the double-load | Add a dedicated command generation/nonce so `applyPageCommand()` is idempotent; `didFinish` updates state without re-enqueuing `.load` | Test: a single `navigate()` results in exactly one `load(_:)` call (spy on the web view) |

### Phase 2 — Make login usable (tab UX + recovery)

| PR | Change | Acceptance |
|---|---|---|
| **2.1** Render all tabs | Keep every tab's `WKWebView` in the hierarchy (opacity/z-index or an `NSView`-swapping representable) so background tabs keep live JS/form state; surface popup/overflow tabs (⌘1…⌘9, ⌥⌘←/→ exist; add overflow menu + middle-click close) | Test: start login in tab A, switch to B, switch back, form state + URL survive; popup tab reachable by ⌘2 |
| **2.2** Replace the dead agent bridge | Decide: wire `AgentBridge` to a **local, opt-in** Unix-socket transport (0600, consent gate, no TCP port) **or** delete it. Do not leave it as unwired code. | If kept: CLI smoke script drives a tab, no TCP listener, consent gate tested. If deleted: grep for `AgentBridge` hits nothing. |
| **2.3** Per-site privacy control | Host allowlist persisted next to website data, page-action toggle, rebuild + recompile rules on change; expose `lastBuildError` in UI | Turning privacy off for `mail.google.com` then reloading reaches the inbox |

### Phase 3 — Ship safely

| PR | Change | Acceptance |
|---|---|---|
| **3.1** Real signing | `Browsair.entitlements` (explicit sandbox decision), Developer ID identity + hardened runtime + notarization in `package-dmg.sh`, version sourced from `Info.plist` (kill the hardcoded `0.2.0`) | `codesign -dvv` shows a TeamIdentifier; `spctl -a` accepts; Keychain `com.browsair.ai` item survives a rebuild |
| **3.2** Unify AI auth | Keep `AIAuth` + API keys; **delete** `OAuthConnect.swift` (loopback `NWListener` + hardcoded `b1a00492-…` Grok CLI client ID); unify behind one surface; fix the `discovered.first!` force-unwrap at `AISettingsView.swift:82` | No `NWListener` in the product; no borrowed client IDs; no force-unwraps in `Sources/` |

### Phase 4 — Usability features (post-login)

| PR | Change | Acceptance |
|---|---|---|
| **4.1** | Find-in-page (`performFind`/`findAll`), zoom in/out/reset, fullscreen (`toggleFullScreen`) | ⌘F finds + highlights; ⌃⌘F fullscreen |
| **4.2** | Downloads (`WKNavigationActionPolicy.download` + `WKDownloadDelegate`) + download manager | A PDF link downloads and is cancellable |
| **4.3** | History + Bookmarks persisted to app support; restore previous tabs on launch (`NSQuitAlwaysKeepsWindows`) | Relaunch restores tabs; history in the menu |
| **4.4** | Password autofill via `ASCredentialProviderViewController` + Keychain | macOS offers a saved credential on a login form |
| **4.5** | Replace `AISidebarView.webViewCache` static dict with a tab-scoped weak reference; bound it | No unbounded static growth across tab churn |

---

## 4. Sequencing recommendation

Ship **0.1 + 1.1 + 1.2 + 1.3** as the first release candidate. That is: drop the dead engine (and its false test failure), make the blocker actually block, fix the popup lifecycle, and prove cookies survive relaunch — together these are what "log into my email and stay logged in" actually depends on. Phase 0.2/0.3 (ATS split, CI) land alongside as the truth check.

## 5. Open risks

- **R1 (was the big one, now resolved as a defect, not a question):** the ruleset *does* load (the prior audit confirmed the compiled binary on disk), but its `url-filter:".*"` + `if-domain` shape is invalid per Apple's docs, so it is inert. PR 1.1 must be validated from **inside the app or a UI-test target** — `WKContentRuleListStore` never calls its completion handler in a plain CLI tool.
- **R2:** `browsair://` OAuth callbacks require LaunchServices registration of a real signed `.app`; they will not fire for a bare `swift run` binary. If provider OAuth stays (post-PR 3.2), state this as a hard requirement.
- **R3:** the two-process cookie test (PR 1.3) needs a way to launch the built bundle twice in CI; budget for a small harness (or an XCUITest).
- **R4:** ad-hoc signature churn may already have orphaned `com.browsair.ai` Keychain entries; reconcile after moving to Developer ID.
