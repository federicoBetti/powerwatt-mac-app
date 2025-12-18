# Developer Release Guide

This document explains how to cut a tagged release, verify the generated artifacts, and test the Sparkle update flow end-to-end.

## 1. Prepare the release
1. Ensure `main` contains everything you want to ship.
2. Pull the latest changes locally and make sure the workspace is clean.
3. Decide on the next semantic version `X.Y.Z`.
4. Create an annotated tag and push it:
   ```bash
   git tag -a vX.Y.Z -m "PowerWatt vX.Y.Z"
   git push origin vX.Y.Z
   ```
   The GitHub Actions workflow (`.github/workflows/releases.yml`) will start automatically.

## 2. Verify GitHub Release assets
1. Wait for the "Release" workflow to finish (runs on `macos-latest`).
2. Open the new release page on GitHub (`https://github.com/federicoBetti/powerwatt-mac-app/releases/tag/vX.Y.Z`).
3. Confirm both assets exist and look reasonable in size:
   - `PowerWatt.dmg`
   - `PowerWatt.zip`
4. (Optional) Download `PowerWatt.zip`, unzip it, and run the app locally to smoke-test the build.

## 3. Verify GitHub Pages appcast
The workflow commits the generated Sparkle appcast back to `docs/appcast.xml` on `main`.

1. Pull `main` after the workflow finishes and confirm `docs/appcast.xml` changed.
2. Fetch the live Pages copy (may take up to a minute to update):
   ```bash
   curl -I https://federicoBetti.github.io/powerwatt-mac-app/appcast.xml
   curl https://federicoBetti.github.io/powerwatt-mac-app/appcast.xml | head
   ```
3. Ensure the `<enclosure>` URL points to the release you just created and that the `<sparkle:edSignature>` attribute is present.

## 4. Test Sparkle updates with a debug feed
`UpdaterManager` reads `debug_appcast_url` from `UserDefaults` (Debug builds only). Use this to test staged feeds before publishing to production.

1. Host a test `appcast.xml` (for example, run `python3 -m http.server 9000` inside a folder that contains the file).
2. Point the debug override at your test feed:
   ```bash
   defaults write com.fbetti44.PowerWatt debug_appcast_url "http://localhost:9000/appcast_test.xml"
   ```
3. Launch a Debug build and use **Check for Updates…** from the menu. Sparkle will read from the override instead of the production feed.
4. When finished testing, remove the override:
   ```bash
   defaults delete com.fbetti44.PowerWatt debug_appcast_url
   ```

## 5. Common failure modes
- **Workflow fails on `generate_appcast`**: ensure the `SPARKLE_EDDSA_PRIVATE_KEY_BASE64` secret is set to the one-line private key produced by `generate_keys -x` and that it matches the public key in `Info.plist`.
- **Release missing assets**: confirm the workflow reached the "Create GitHub Release" step and that `softprops/action-gh-release` had permission (`contents: write`).
- **Pages still serves an old appcast**: the commit to `main` may have been rejected. Check the workflow logs for the `git-auto-commit-action` step and rerun if necessary.
- **Sparkle test feed ignored**: the debug override only works in Debug builds and requires a valid `http` or `https` URL. Check the override value with `defaults read com.fbetti44.PowerWatt debug_appcast_url`.

## 6. Future Gatekeeper / notarization phase
Gatekeeper hardening is explicitly deferred for now, but plan on a follow-up iteration with these steps:

1. **Developer ID signing**: Import the Developer ID Application certificate into the workflow (see `docs/CI_SECRETS.md` for the placeholder secret names) and codesign the Release build with the real identity instead of ad-hoc signing.
2. **Notarization**: Use `xcrun notarytool submit` with the App-Specific Password credentials. Wait for the notarization status, fail the job if it returns an error.
3. **Stapling**: Run `xcrun stapler staple PowerWatt.app` (and optionally the DMG) before uploading artifacts.
4. **Docs refresh**: Once notarized builds ship, update `docs/index.html` (install instructions) and any README guidance to remove the “right-click → Open” workaround.

Track this list when you're ready to tackle Gatekeeper; nothing in the current workflow depends on these steps yet.


