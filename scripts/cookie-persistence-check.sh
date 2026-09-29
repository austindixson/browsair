#!/usr/bin/env bash
#
# Two-process cookie-persistence check (audit F3 / PR 1.3).
#
# The claim under test (README.md): login cookies survive an app relaunch, because WebKit keys
# persistent website data on the app's CFBundleIdentifier. `swift test` cannot prove this — it runs
# in a single process and cannot fork two `WKWebsiteDataStore`-owning processes.
#
# This harness compiles a tiny WebKit app that:
#   process A: loads a real page, sets document.cookie, exits
#   process B: a brand-new process reads WKWebsiteDataStore.default().httpCookieStore
# If B sees the cookie, persistence works end to end.
#
# IMPORTANT precondition this check exists to document: WebKit only writes *durable* storage for a
# properly-installed app — a registered bundle (CFBundleIdentifier present in LaunchServices) with
# its network-process identifier (com.apple.WebKit.WebContent) signed. A bare ad-hoc-signed
# `swift build` binary reports NO bundle identifier at all, so it has no identity to key storage
# on and cookies are silently dropped. If this harness prints INCONCLUSIVE (READ count=0), that is
# the F3 root cause reproducing itself: run against a Developer-ID-signed .app installed under
# /Applications for the PASS path.
#
#   scripts/cookie-persistence-check.sh [probe-url]
#
# Exit 0 = cookie survived across processes (PASS).
# Exit 1 = A wrote a cookie but B did not see it (FAIL — persistence regressed).
# Exit 2 = environment precondition unmet (INCONCLUSIVE — see above).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build/cookie-check"
PROBE_URL="${1:-https://example.com/}"
PROBE_ID="dev.ghost64.browsair.cookiecheck"
COOKIE_NAME="browsair_persist_probe"

rm -rf "$WORK"; mkdir -p "$WORK/CookieCheck.app/Contents/MacOS"

# --- tiny WebKit probe ----------------------------------------------------
cat > "$WORK/main.swift" <<'SWIFT'
import AppKit
import WebKit

// argv: <set|read> <url> <cookieName>
let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "set"
let urlString = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "about:blank"
let cookieName = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "probe"

func done(_ s: String) { print("RESULT \(s)"); fflush(stdout); exit(0) }

print("bundleID=\(Bundle.main.bundleIdentifier ?? "nil")")

// Persistent, disk-backed store. `.default()` is only genuinely persistent for an app with a real
// registered identity; for a bare binary it silently behaves as ephemeral (audit F3).
let config = WKWebViewConfiguration()
config.websiteDataStore = .default()
let webView = WKWebView(frame: .zero, configuration: config)

final class Holder: NSObject, WKNavigationDelegate {
    let f: (WKWebView) -> Void
    init(_ f: @escaping (WKWebView) -> Void) { self.f = f }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { f(w) }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { print("NAV_FAIL \(e.localizedDescription)"); f(w) }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { print("PROVISIONAL_FAIL \(e.localizedDescription)"); f(w) }
}
var holder: Holder?
DispatchQueue.main.asyncAfter(deadline: .now() + 12) { done("TIMEOUT") }

if mode == "set" {
    guard let url = URL(string: urlString) else { done("BADURL"); exit(0) }
    let h = Holder { w in
        w.evaluateJavaScript("document.cookie='\(cookieName)=persisted-ok; path=/'; document.cookie") { v, e in
            if let e { done("EVALERR \(e.localizedDescription)") }
            // Hold the run loop so WebKit flushes the cookie to disk before we exit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { done("SET v=\(v ?? "nil")") }
        }
    }
    holder = h; webView.navigationDelegate = h
    webView.load(URLRequest(url: url))
} else {
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
        let match = cookies.first { $0.name == cookieName }
        done("READ count=\(cookies.count) value=\(match?.value ?? "ABSENT")")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.run()
SWIFT

echo "Compiling cookie probe..."
if ! swiftc -O "$WORK/main.swift" -o "$WORK/CookieCheck.app/Contents/MacOS/cookiecheck" 2> "$WORK/compile.log"; then
    echo "probe failed to compile:"; cat "$WORK/compile.log"; exit 2
fi

cat > "$WORK/CookieCheck.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$PROBE_ID</string>
<key>CFBundleName</key><string>CookieCheck</string>
<key>CFBundleExecutable</key><string>cookiecheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

# Ad-hoc sign the bundle. NOTE: ad-hoc signing is exactly why the PASS path may not trigger here —
# a shipped Developer-ID-signed bundle is what WebKit trusts for durable storage.
codesign --force --sign - "$WORK/CookieCheck.app/Contents/MacOS/cookiecheck" 2>/dev/null || true
codesign --force --sign - "$WORK/CookieCheck.app" 2>/dev/null || true
# Register with LaunchServices so the identity is resolvable (best-effort).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$WORK/CookieCheck.app" 2>/dev/null || true

APP="$WORK/CookieCheck.app/Contents/MacOS/cookiecheck"

# Start from a clean slate so we are not reading a stale cookie from a previous run.
rm -rf "$HOME/Library/HTTPStorages/$PROBE_ID" "$HOME/Library/HTTPStorages/$PROBE_ID.binarycookies" 2>/dev/null || true

echo "Process A: setting cookie '$COOKIE_NAME' via $PROBE_URL ..."
A_OUT="$("$APP" set "$PROBE_URL" "$COOKIE_NAME" 2>&1)"
echo "$A_OUT" | grep -E "bundleID|RESULT|FAIL" | sed 's/^/       /'
A_RESULT="$(printf '%s\n' "$A_OUT" | grep -o 'RESULT SET.*' | head -1)"

echo "Cookie artifacts under ~/Library:"
find "$HOME/Library/HTTPStorages" "$HOME/Library/Containers" -iname "*$PROBE_ID*" 2>/dev/null | sed 's/^/       /' || true

echo "Process B: reading cookie in a fresh process (new WKWebsiteDataStore) ..."
B_OUT="$("$APP" read "about:blank" "$COOKIE_NAME" 2>&1)"
echo "$B_OUT" | grep -E "RESULT" | sed 's/^/       /'
B_RESULT="$(printf '%s\n' "$B_OUT" | grep -o 'RESULT READ.*' | head -1)"

# --- verdict --------------------------------------------------------------
if printf '%s' "$B_RESULT" | grep -q "value=persisted-ok"; then
    echo "PASS: cookie written in process A was readable in a fresh process B."
    echo "      WebKit persisted it under the bundle id $PROBE_ID."
    exit 0
elif printf '%s' "$B_RESULT" | grep -q "value=ABSENT"; then
    if printf '%s' "$A_RESULT" | grep -q "RESULT SET"; then
        # A ran JS that set a cookie, but B did not see it.
        echo "INCONCLUSIVE: process A set the cookie but fresh process B read none."
        echo "  This is the F3 root cause: WebKit is not persisting durable storage for this"
        echo "  bundle in this environment (ad-hoc signature / unregistered WebContent helper)."
        echo "  Re-run against a Developer-ID-signed .app installed under /Applications to get PASS."
        exit 2
    else
        echo "INCONCLUSIVE: process A did not complete a page load (no network / page load failed)."
        echo "  Re-run with a reachable URL, e.g. scripts/cookie-persistence-check.sh https://example.com/"
        exit 2
    fi
else
    echo "INCONCLUSIVE: could not parse read result ('$B_RESULT')."
    exit 2
fi
