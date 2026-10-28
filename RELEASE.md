# Releasing Kanso

Pipeline: test → build (hardened runtime) → sign → styled DMG → notarize → staple → verify.
CI (`.github/workflows/swift.yml`) does all of it; `scripts/release.sh` does the same by hand on a Mac.

## What CI does

| Trigger | Job `test` | Job `package` |
|---|---|---|
| pull request | resolve, `swift test`, release build, UI snapshots (light + dark), best-effort screen recording | – |
| push to `main` | same | builds the DMG. **Unsigned/ad-hoc if secrets are missing**, signed + notarized + stapled + verified if present |
| tag `vX.Y.Z` | same | same, version from the tag, then a **draft** GitHub release with the DMG |

QA artifacts (`qa-snapshots-and-recordings`): PNG of every screen in both appearances, plus `popover.mov`/`desktop.png` when the runner allows screen capture (runners may deny Screen Recording; that step never fails the build). Snapshots draw solid fallbacks for glass, so real Liquid Glass still needs eyes on a Mac.

**What flips signing on:** all six secrets below exist as repository secrets. The `package` job computes `HAVE_APPLE_SECRETS` from them; no workflow edit is needed.

## Secrets (exact names)

| Secret | Where it comes from |
|---|---|
| `APPLE_TEAM_ID` | developer.apple.com → Membership details (10 characters) |
| `APPLE_DEVELOPER_ID_CERT_P12` | Create a *Developer ID Application* certificate (Certificates, IDs & Profiles), export it with its private key from Keychain Access as .p12, then `base64 -i cert.p12 \| pbcopy` |
| `APPLE_DEVELOPER_ID_CERT_PASSWORD` | the password chosen during that .p12 export |
| `APPLE_API_KEY_ID` | App Store Connect → Users and Access → Integrations → Team Keys (key ID) |
| `APPLE_API_ISSUER_ID` | same page, Issuer ID at the top |
| `APPLE_API_PRIVATE_KEY` | contents of the downloaded `AuthKey_XXXX.p8` (PEM text; downloadable once). Key access role: Developer is enough for notarytool |

An API key is used instead of Apple ID + app-specific password, which breaks whenever the password changes. Needs the paid Apple Developer Program membership.

## Manual release on a Mac

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_API_KEY_ID=... APPLE_API_ISSUER_ID=...
export APPLE_API_KEY_PATH=~/keys/AuthKey_XXXX.p8     # or APPLE_API_PRIVATE_KEY with the PEM text
scripts/release.sh 1.0.0 1
```

Steps it runs: `swift test` → `app/build.sh` (signs `kanso-cli` then the app, `--options runtime --timestamp`, `release/entitlements.plist`) → `scripts/make-dmg.sh` (create-dmg; background from `release/dmg-background.swift`, Kanso.app + Applications link) → `scripts/notarize.sh` (`xcrun notarytool submit --wait`, fails unless Accepted, then `stapler staple`) → `scripts/verify-release.sh` (`codesign --verify --deep --strict`, hardened-runtime flag check, `spctl --assess --type execute` and on the DMG, `stapler validate`).

## Status

Authored on a Linux host: **none of this has run yet.** First green run on a Mac runner is expected to need small fixes (create-dmg Finder scripting on headless runners, linker flag vs. runner Xcode). Not covered yet: Sparkle/update feed, Homebrew cask, sandbox/security-scoped bookmarks.
