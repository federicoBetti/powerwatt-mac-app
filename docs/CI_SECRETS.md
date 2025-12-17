# CI Secrets

This repository ships releases via GitHub Actions (`.github/workflows/releases.yml`). The workflow needs a small set of secrets so it can sign Sparkle updates and, later, support notarization.

## Required now

### `SPARKLE_EDDSA_PRIVATE_KEY_BASE64`
Sparkle update ZIPs must be signed with the private Ed25519 key that pairs with the public key embedded in `PowerWatt/Info.plist` (`SUPublicEDKey`).

1. Install the Sparkle tools locally (or reuse the copy from `SPARKLE_VERSION` in the workflow) and run:
   ```bash
   generate_keys
   generate_keys -x
   ```
   - The first command prints the public key (already stored in `Info.plist`).
   - The `-x` flag writes the private key to `sparkle_private_key_ed25519.pem`.
2. Base64-encode the private key file:
   ```bash
   base64 sparkle_private_key_ed25519.pem | tr -d '\n'
   ```
3. In the GitHub repository settings → **Secrets and variables** → **Actions**, create a new secret named `SPARKLE_EDDSA_PRIVATE_KEY_BASE64` and paste the single-line base64 string.
4. Delete the plaintext private key file after uploading the secret.

The workflow decodes this secret into a temporary file (see the "Generate appcast" step) and removes it immediately after generating `docs/appcast.xml`.

#### Rotation
- Re-run `generate_keys` to create a new keypair.
- Update `Info.plist` with the new **public** key before shipping a release.
- Replace the secret value in GitHub with the new **private** key.
- Do not reuse old private keys; revoke them by deleting the old secret entry.

## Optional (future Gatekeeper phase)
When you're ready to notarize and staple releases, you'll need additional credentials:

- `APPLE_DEVELOPER_ID_CERT`: base64-encoded `.p12` containing the Developer ID Application certificate.
- `APPLE_DEVELOPER_ID_CERT_PASSWORD`: password for the `.p12` file.
- `NOTARYTOOL_APPLE_ID`, `NOTARYTOOL_TEAM_ID`, `NOTARYTOOL_PASSWORD`: credentials for `xcrun notarytool` (usually an App-Specific Password).

Documented here so the follow-up Gatekeeper/notarization phase can plug them into the workflow without guesswork.
