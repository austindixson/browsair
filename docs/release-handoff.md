# Release handoff — Browsair v0.3.0

Repo: **https://github.com/austindixson/browsair** (private) · origin set · `main` pushed.
Tag **`v0.3.0`** is intentionally **not** created/pushed yet — it triggers the
notarized Release the instant it lands, and that needs the signing secrets below.

The CI workflow is wired on `main` (build/test + ad-hoc package; Developer-ID
package job skips cleanly until the cert secrets exist). The signing identity
secret `BROWSAIR_SIGN_IDENTITY` is already set. The other five secrets must come
from you (they are your credentials / Apple secrets and cannot be produced by an
agent that has no access to your login password or App Store Connect).

## Secrets still needed (repo = austindixson/browsair)

| Secret | Source |
|---|---|
| `BROWSAIR_SIGN_IDENTITY` | ✅ already set (`32E042BC4994E1002DE3E05F8010AB527FCE76B6`) |
| `BROWSAIR_CERT_P12_BASE64` | export Developer ID cert from login Keychain (below) |
| `BROWSAIR_CERT_P12_PASSWORD` | the password you give that export |
| `APPLE_API_KEY` | contents of the App Store Connect `.p8` |
| `APPLE_API_KEY_ID` | App Store Connect Key ID |
| `APPLE_API_ISSUER` | App Store Connect Issuer ID |

## Run these in YOUR terminal (agent shell can't — needs your login password + ASC access)

Open a normal Terminal on this Mac. `gh` is already authenticated as
`austindixson` (keyring). If a fresh shell doesn't see it, `gh auth login` or
`export GH_CONFIG_DIR="$HOME/.config/gh"`.

### 1. Export the Developer ID cert + private key to a .p12
macOS will prompt for your login password once (GUI) — that is expected and is
why this step cannot run in a non-interactive agent.
```
security export -k "$HOME/Library/Keychains/login.keychain-db" \
  -t certs -f pkcs12 -l "Developer ID Application: Austin Dixson (236GD9QC39)" \
  -k "$HOME/Library/Keychains/login.keychain-db" -p "" -o /tmp/browsair-dev-id.p12
```
That exports with an **empty** p12 password. If you prefer a password, replace
`-p ""` with `-p 'YOURP12PASS'` and use that same value as the next secret.
(If macOS refuses to export the private key, do it from Keychain Access GUI:
right-click "Developer ID Application: Austin Dixson (236GD9QC39)" → Export… →
.p12, set a password.)

### 2. Set the two cert secrets
```
cd /Users/ghost64/Desktop/PROJECTS/browsair
base64 -i /tmp/browsair-dev-id.p12 | gh secret set BROWSAIR_CERT_P12_BASE64 -R austindixson/browsair
printf '%s' 'YOURP12PASS' | gh secret set BROWSAIR_CERT_P12_PASSWORD -R austindixson/browsair
# (empty-password export -> skip the second line, or set it to '')
rm -f /tmp/browsair-dev-id.p12   # delete the plaintext p12 once the secret is set
```

### 3. Create + set the App Store Connect API key (for notarization)
App Store Connect → Users and Access → Integrations → App Store Connect API →
create a key with role **Developer** (or Admin). Download the `.p8` (one-time
download). Note the **Key ID** and the **Issuer ID** (top of that page).
```
gh secret set APPLE_API_KEY          -R austindixson/browsair < "$HOME/secrets/AuthKey_XXXXXXXXXX.p8"
printf '%s' 'YOUR_KEY_ID'   | gh secret set APPLE_API_KEY_ID   -R austindixson/browsair
printf '%s' 'YOUR_ISSUER_ID'| gh secret set APPLE_API_ISSUER   -R austindixson/browsair
```

### 4. Confirm, then fire the release
```
gh secret list -R austindixson/browsair        # expect all six
cd /Users/ghost64/Desktop/PROJECTS/browsair
git tag v0.3.0
git push origin v0.3.0                          # → Release workflow signs + notarizes
gh run watch -R austindixson/browsair           # watch it; notarize takes a few minutes
```
On success the notarized, stapled `dist/Browsair-0.3.0.dmg` is attached to a
GitHub Release. The Release job **fails safe** (no unsigned artifact published)
if any secret is missing or wrong.

## Alternative: drive an agent to do it
If you resume an agent that CAN reach your login keychain password interactively
(or you export the values yourself and paste them), this is the ask:

> In /Users/ghost64/Desktop/PROJECTS/browsair, with `export
> GH_CONFIG_DIR="$HOME/.config/gh"`: (1) export the Developer ID Application cert
> "…Austin Dixson (236GD9QC39)" from login.keychain-db to a .p12 (you will be
> prompted for the login password); (2) set the six GitHub secrets
> BROWSAIR_SIGN_IDENTITY, BROWSAIR_CERT_P12_BASE64, BROWSAIR_CERT_P12_PASSWORD,
> APPLE_API_KEY, APPLE_API_KEY_ID, APPLE_API_ISSUER per docs/release-handoff.md;
> (3) create tag v0.3.0 and `git push origin v0.3.0` to trigger the notarized
> release; (4) watch the Release run and report the published asset. Never echo
> secret values.

## Notes
- `gh` auth: my tool shell runs with a redirected `HOME`
  (`/Users/ghost64/.opengrok/home`), so `gh` here needs `GH_CONFIG_DIR` pointed
  at the real `/Users/ghost64/.config/gh`. Your normal terminal does not need
  that.
- The release workflow gates the tag against `Info.plist`
  `CFBundleShortVersionString` (now `0.3.0`); a mismatched tag is rejected before
  signing.
