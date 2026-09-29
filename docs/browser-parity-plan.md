# Browsair — Audit and Browser-Parity Improvement Plan

**Status:** Active plan (supersedes `improvement-prd.md` for v0.3+)
**Date:** 2026-09-27
**Baseline:** `swift build` OK after clearing a stale `.build`; 47/47 tests pass

---

## 1. What Browsair is made of

**Browsair is not Chromium.** It is a Swift Package Manager executable: SwiftUI + AppKit chrome
around Apple's **WebKit** (`WKWebView`), rendering with the WebContent process. Blink/V8 are not
involved for normal browsing.

There is a **second, separate Chromium engine in the repo**: `Obscura` v0.2.1, a 94 MB Mach-O
arm64 binary at `Sources/Browsair/Resources/Engine/obscura` (plus an 86 MB `obscura-worker`),
driven over the Chrome DevTools Protocol by `Engine/EngineProcess.swift` and `Engine/CDPClient.swift`.
It is **dead code**: the interactive path never starts it, and the README already says so.

| Surface | Engine | Drives login today? |
|---|---|---|
| `UI/PageSurfaceView.swift` | WebKit `WKWebView` | **Yes — the only live page surface** |
| `Engine/HeadlessSession.swift` | Obscura (Chromium) via CDP | No — never started by the UI |
| `Vendor/obscura/` + bundled binary | 180 MB on disk, gitignored/untracked | No |

Two engines is the root architectural cost of this repo. Everything in §3 follows from committing
to WebKit for browsing.

---

## 2. The login bug: why signing in fails

Five independent faults. Any one of them alone can break a sign-in.

### F1 — No popup/window-open handling → the OAuth leg dies silently

`PageSurfaceView.swift:62` declares `Coordinator: NSObject, WKNavigationDelegate` and never
implements `webView(_:createWebViewWith:for:windowFeatures:)`. WebKit's documented default for an
unimplemented delegate method is to **ignore the request**.

Consequence: `accounts.google.com/signin/v1/consent` and `github.com/login/device/authorize`,
"Sign in with Apple", Microsoft/Gmail "choose an account" interstitials, and any SSO leg opened
with `window.open` / `target="_blank"` produce **no visible window and no error**. The user clicks
the button and nothing happens. Combined with F4 (no tab switching) and F5 (no history), there is
no way to even discover that a window was requested.

### F2 — Address bar mangles dev/local targets

`BrowserSession.normalizeURL` decides "is this a URL?" with `raw.contains(".")`, so any input
containing a space is always searched.

Measured on the current rule (`swift` probe):

| Typed | Current result | Correct |
|---|---|---|
| `localhost:3000` | `https://duckduckgo.com/?q=localhost:3000` | `http://localhost:3000` |
| `localhost` | `https://duckduckgo.com/?q=localhost` | `http://localhost` |
| `/settings/profile` | `https://duckduckgo.com/?q=/settings/profile` | resolve against current page |
| `?q=hello` | searched | resolve against current page |
| `#section` | searched | in-page fragment |
| `mailto:a@b.com` | `https://mailto:a@b.com` | hand to `NSWorkspace` |
| `file:///tmp/x.html` | `https://file:///tmp/x.html` | load or refuse deliberately |
| `127.0.0.1:8080/login` | correct | — |

So typing a local or relative target sends a DuckDuckGo search, not a login page.

### F3 — Cookies may not survive relaunch (unproven, but load-bearing)

`PageSurfaceView.swift:37` sets `configuration.websiteDataStore = .default()` and passes **no
`WKWebsiteDataStoreConfiguration`**. For an unsandboxed app launched as a bare SwiftPM binary, this
is the classic way to end up with a store that does not persist cookies across launches.

Filesystem evidence, stated honestly in both directions:

- **Against persistence:** `~/Library/WebKit/dev.ghost64.browsair/WebsiteData/Default/` holds only
  `salt`, two hashed-origin folders (LocalStorage, CacheStorage) — **no `Cookies` sqlite file**, after
  ~4 weeks of runs and a recorded on-disk content rule list.
- **For persistence:** `~/Library/HTTPStorages/dev.ghost64.browsair.binarycookies` exists (that is
  `URLSession`/CFNetwork storage, which WebKit page navigation does *not* share, so it is weak
  counter-evidence).
- The 47 passing tests never assert that a cookie set in process A is visible in process B.

Whatever the truth, the fix is the same and it is cheap: construct the store explicitly and prove
persistence with a two-process test (PR 1.1). The README's claim that data persists under
`~/Library/Application Support/Browsair` is false either way — WebKit keeps data under
`~/Library/WebKit/<bundle-id>/`.

### F4 — Popups have nowhere to go, and the tab UI hides them

`BrowserChromeView.swift:126` renders `PageSurfaceView` **only for `session.activeTab`**. `TabModel`
is `Identifiable` with a stable UUID, so background tab views are retained rather than destroyed —
but only one tab is ever in the view hierarchy, so anything opened in another tab is **invisible with
no way to notice**. There is no tab-switch shortcut (⌘1…⌘9 / Ctrl-Tab), no overflow menu, and the
tab strip is a bare horizontal `ScrollView`.

So even the OAuth legs that *don't* need `window.open` are easy to lose: a tab opened in the
background looks like a hang.


### F5 — Missing browser affordances and shared state

No find-on-page, no downloads, no password autofill, no reader mode, no zoom, no PDF viewer hook,
no fullscreen (`NSWindow` style mask is never touched), no secure-input context for password fields,
no devtools, no per-site permission prompts (camera/geolocation/notification grants silently fail),
and no keyboard access to switch tabs. A login that succeeds still cannot be *used*.

### F6 — Tracker blocking is shipped without a first-party exemption

`PrivacyPolicy.contentBlockerJSON` builds
`{"trigger":{"url-filter":".*","if-domain":["*google-analytics.com"]},"action":{"type":"block"}}`
with **no `load-type: third-party`**. The Swift-side `shouldBlock(url:firstPartyHost:)` *does*
implement first-party exemption — but that function is never what ships to WebKit; the JSON is.

Worst case here is Google: analytics endpoints can be served from the same registrable domain the
login page runs on, so a non-`load-type` rule can block the document itself. **R1 in §5 confirms the
ruleset really does compile and load**, so this is a live risk rather than a theoretical one.

---

## 3. Dead code and contradictions

| Finding | Evidence |
|---|---|
| `AgentBridge` has **zero production callers** | `execute(...)` is called only from `Tests/BrowsairTests/AgentRuntimeTests.swift`; nothing in `UI/` or `Browser/` reaches it |
| ⌘L is a no-op | Posts `.browsairFocusAddressBar`; **no `addObserver` exists anywhere**; `BrowserChromeView.swift:113` comment admits it |
| ⌘W is double-bound | App shortcut **and** `CommandGroup(replacing: .newItem)`; "Close Window" is not customized |
| `.searchable` is absent | No browser search, yet a full AI chat stack exists |
| The AI sidebar sends **no page content** | `AISidebarView.swift:51` passes `selectedText: nil, inspectedText: nil`; the system prompt promises "use only the supplied page context" that is never supplied |
| Two parallel auth stacks | `AI/AIAuth.swift` + `AI/OAuthConnect.swift` vs `AI/OAuthAccounts.swift`, never unified |
| 180 MB shipped for dead code | `Resources/Engine/obscura` + `obscura-worker`, copied into the .app by `package-dmg.sh` |
| `NSAllowsArbitraryLoads = true` | `Resources/Info.plist` disables ATS app-wide — kills `http://` autofill targets *and* is a review/App-Store blocker |
| Ad-hoc signing, no entitlements file | `codesign -dvv` → `Signature=adhoc`, `TeamIdentifier=not set`; `find . -name '*.entitlements'` → nothing. **Ad-hoc signatures are not stable across rebuilds, so Keychain access groups break between builds** |
| README claims a storage path that is false | "Persists website data under `~/Library/Application Support/Browsair`" — nothing in `Sources/` writes there (F3) |

Note: `~/Library/Application Support/Browsair/cookies.json` **does exist** on this machine
(3 Google cookies, mtime today). Nothing in `Sources/` writes there — it came from another
tool. Treat it as a red flag for two competing cookie stores, and never make Browsair read it.

---

## 4. Plan — phases with acceptance criteria

Each PR is independently shippable and testable. Phases 0–2 are what "log into my email" needs.

### Phase 0 — Truth and safety (no behavior change)

| PR | Change | Acceptance |
|---|---|---|
| **0.1** | Delete Obscura engine from the default product: drop the two bundled binaries from `Resources/Engine`, remove `.copy("Resources/Engine")` and the icon excludes from `Package.swift`, delete `Engine/`, `Vendor/`, `fetch-engine.sh`, `EngineIsolationTests.swift`, `ObscuraEngineTests.swift`, `CDPTypesTests.swift`; fix `README.md` + `package-dmg.sh` | `swift build` green; binary size drops ~180 MB; grep for `obscura`/`CDP` returns only docs |
| **0.2** | Content-rule-list assertion **inside the app or a UI-test target** (a CLI probe hangs — see R1): compile the shipped ruleset and record whether it loads, plus which hosts it blocks | Test target asserts the rule list compiles and that listed first-party documents are not blocked |
| **0.3** | Split `Info.plist` into `AppInfo.plist` (bundle identity, URL scheme, icon) and `AppInfo.debug.plist` (keeps `NSAllowsArbitraryLoads`); wire via the existing `-sectcreate` | `codesign -dvv` release build shows no ATS exception; debug build still allows `http://localhost` |

### Phase 1 — Make login work (highest priority)

| PR | Change | Acceptance |
|---|---|---|
| **1.1** | Explicit persistent store: build `WKWebsiteDataStoreConfiguration` with `store = .default()` **only if** `dataStore.exists` semantics can be verified; otherwise persistent `WebsiteData` under `~/Library/Application Support/Browsair/WebsiteData`. Set `httpCookieStore` access explicitly. Add `BrowserSession.dataStoreURL` | **Regression test:** set `WKHTTPCookieStore` cookie in process A, terminate, relaunch, assert presence. Must fail on `main`, pass after |
| **1.2** | Implement `webView(_:createWebViewWith:for:windowFeatures:)` → `session.openTab(...)`, present the new tab immediately, and handle `WKUIDelegate` `runJavaScriptTextInputPanel` etc. | **Integration test:** page calling `window.open` yields a live tab with the target URL and it becomes active |
| **1.3** | Replace `normalizeURL` with the validated classifier: explicit scheme passthrough → fragment → relative against current page → known-search-engine in-place → `localhost`/`.local` → IPv4 (octet-validated) / IPv6 literal → `www.`-strippable dotted host with alphabetic TLD ≥2 **and** valid port → else search. Non-web schemes (`mailto:`, `tel:`) → `NSWorkspace` | Table-driven test over the 28 cases in §2 + the 8 in the table; `.local` and bare `localhost` covered |
| **1.4** | Fix ruleset: add `"load-type": ["third-party"]` to every rule, drop the prefix heuristics (`ads.`/`ad.`/`pixel.`/`analytics.`) into real rules, add per-host `url-filter`, and **stop swallowing the compiler error** at `PageSurfaceView.swift:75-79` (`{ list, _ in guard let list else { return } }` silently drops failures into the void) | In-app assertion (0.2) shows first-party login documents are **allowed** for google.com, microsoftonline.com, github.com, appleid.apple.com, fastmail.com, protonmail.com; a compile failure surfaces as a visible engine-status string |
| **1.5** | Per-site privacy control: host-level allowlist persisted next to website data; UI toggle in page action menu; ruleset rebuilt + recompiled on change | Turning privacy off for `mail.google.com` then reloading reaches the inbox |

### Phase 2 — Tab UX and state consistency

| PR | Change | Acceptance |
|---|---|---|
| **2.1** | Render **all** tabs' `PageSurfaceView`s and show only the active one (`.opacity`/`zIndex`, or an `NSView`-swapping `NSViewRepresentable`) so background tabs keep live WebKit state; add ⌘1…⌘9 / ⌥⌘←→ / Ctrl-Tab switching, tab overflow menu, and middle-click close | Test: start login in tab A, switch to B, switch back, assert form state + URL survive; popup tab reachable by ⌘2 |
| **2.2** | `WKNavigationDelegate` completeness: `decidePolicyFor navigationAction/response` (record history, honor downloads via `WKNavigationActionPolicy.download`), `didFailProvisionalNavigation` with a real error page, `webViewWebContentProcessDidTerminate` → reload prompt | Sign-out, 404, and a killed WebContent process all produce recoverable UI |
| **2.3** | History + Bookmarks: persist to app support, `NSMenu` Recent/Bookmarks, restore on launch (`NSQuitAlwaysKeepsWindows`) | Relaunch restores the previous tabs; history appears in the menu |
| **2.4** | Find-on-page (`performFind`/`findAll`), zoom in/out/reset, fullscreen via `toggleFullScreen`, download manager with `WKDownload` delegate | Cmd-F finds and highlights; a PDF link downloads; ⌃⌘F goes fullscreen |

### Phase 3 — Credentials and agent surface

| PR | Change | Acceptance |
|---|---|---|
| **3.1** | Password autofill: `ASCredentialProviderViewController` (AuthenticationServices) + Keychain read/write for login forms | On a login form, macOS offers a saved credential and fills it |
| **3.2** | Properly wire `AgentBridge` into the app with a **local, opt-in** transport (Unix socket under app support, 0600, user-consent gate). Do **not** open a TCP port. Commands: `getState`, `navigate`, `readPageText`, `inspect`, plus new `act` (click/type into a resolved element) | CLI smoke script drives a tab; no listener on TCP; consent gate tested |
| **3.3** | Decide the AI stack: keep `AIAuth` + API keys, **delete** `OAuthConnect.swift` (loopback `NWListener` + hardcoded `b1a00492-…` Grok CLI client ID is a ToS and security problem), unify behind one auth surface; wire real `selectedText`/`inspectedText` into the sidebar; fix the `messages.last!` force-unwrap at `AISidebarView.swift:52` | No `NWListener` in the product; sidebar context block non-empty when text is selected |

### Phase 4 — Distribution

| PR | Change | Acceptance |
|---|---|---|
| **4.1** | Real signing: `Browsair.entitlements` (sandbox decision made explicitly), Developer ID identity from Keychain, hardened runtime, notarize in `package-dmg.sh`; stable bundle identifier so Keychain ACLs persist | `codesign -dvv` shows TeamIdentifier; `spctl -a` accepts; Keychain item survives a rebuild (this is what breaks ad-hoc builds today) |
| **4.2** | CI on macOS: build + `swift test` + privacy probe + a WebKit login-smoke test (set/relaunch cookie) | Red on F1/F3 regressions |

---

## 5. Risks and open questions

- **R1 — RESOLVED (2026-09-27).** The ruleset **does** compile. Evidence:
  `~/Library/WebKit/dev.ghost64.browsair/ContentRuleLists/ContentRuleList-browsair.privacy`
  (9,058 bytes, binary WebKit rule-list format, not JSON) exists on disk. So the `if-domain`-only
  rules are accepted by `WKContentRuleListStore` and privacy blocking is genuinely active.
  The defect is therefore the *opposite* of a no-op: rules lack `"load-type": ["third-party"]`, so
  they can block same-registrable-domain resources — the Google-login risk in F6.
  Note for whoever writes PR 0.2: **`WKContentRuleListStore` never invokes its completion handler in
  a plain CLI tool** (verified — probe returned nothing after 15 s; it needs a running app
  connection / `NSApplication`). Assert the rule list from inside the app or a UI test target, not a
  command-line script.
- **R2:** committing to WebKit means giving up CDP. If agent automation needs Chromium semantics, keep
  Obscura as an *opt-in separate product target*, not in the browsing app.
- **R3 (still open):** whether `WKWebsiteDataStore.default()` without a `WKWebsiteDataStoreConfiguration`
  persists cookies for an unsandboxed SwiftPM binary is **not yet proven** — `~/Library/HTTPStorages/
  dev.ghost64.browsair.binarycookies` does exist, which complicates the earlier read. Settle it with the
  two-process regression test in PR 1.1 before believing either README claim.
- **R4:** ad-hoc signature churn may already have orphaned Keychain entries — reconcile `com.browsair.ai`
  items after moving to Developer ID.
- **R5:** `~/Library/Application Support/Browsair/cookies.json` (3 `google.com` cookies, written today)
  is **not** written by Browsair — no source file references that path, and the app is not running.
  Another tool uses the same directory. Never have Browsair read or merge it.

## 6. Sequencing recommendation

Ship **1.1 + 1.2 + 1.3** as one release candidate. Those three are ~250 lines total, all in
`PageSurfaceView.swift` / `BrowserSession.swift`, and they are what "log into my email" actually depends
on. 0.2 runs alongside as the truth check. Phase 0.1 (delete 180 MB) can land immediately in parallel
since nothing imports the engine.
