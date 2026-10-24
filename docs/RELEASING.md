# Releasing Screentime++

`Config/Version.xcconfig` is authoritative. Use three-component `MARKETING_VERSION`,
increase `CURRENT_PROJECT_VERSION` for every release, and tag `v<MARKETING_VERSION>`.
The app targets macOS 15 and ships universal arm64 + x86_64. CI and Release use
`macos-26` with `/Applications/Xcode_26.4.1.app`; local builds use full Xcode.
The XcodeGen wrapper pins 2.45.4 and verifies the downloaded tool's checksum when
that version is not installed. Commit the generated `Screentime.xcodeproj`.

## Prepare

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
Scripts/verify-version.sh
for script in Scripts/*.sh; do bash -n "$script"; done
swift test
Scripts/xcodegen.sh generate
git diff --exit-code -- Screentime.xcodeproj
Scripts/build.sh
```

`build.sh` builds unsigned Debug products, then applies local ad-hoc signatures.
It does not launch the app or change an installed copy. Ad-hoc output is never a
production release. Universal packaging is not proof of runtime testing on Intel.

## Local signed and notarized release

The login Keychain must contain the Developer ID certificate and private key,
and the `screenlogger-notary` notarytool profile for team `3UX5N7Y8TY`.
Use the SHA-1 fingerprint because two certificates share the display name.
The Sparkle Ed25519 private key is stored under Keychain account
`screentimeplusplus`; feed generation also accepts `SPARKLE_ED_PRIVATE_KEY`.
Never print, commit, or pass private-key contents as command-line arguments.

```sh
export SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)"
Scripts/package-release.sh \
  --expected-tag v0.1.0 \
  --signing developer-id \
  --identity 08304A35FC08F4049CFCE649DE8EFF7195F5F0E7 \
  --team-id 3UX5N7Y8TY \
  --notary-profile screenlogger-notary \
  --output build/releases
Scripts/generate-update-feed.sh \
  --archive build/releases/ScreentimePlusPlus-v0.1.0-macos-universal.dmg \
  --output build/releases/appcast.xml \
  --tag v0.1.0
```

Packaging signs Sparkle inside-out, then the app, using Hardened Runtime and
secure timestamps. It checks Team IDs, signatures, runtime flags, timestamps,
and universal executable architectures. It submits a temporary app ZIP,
staples the app, builds and signs the DMG, submits and staples the DMG, and
checks Gatekeeper and the mounted app. Checksums describe final stapled bytes.
The temporary ZIP is not a release asset. Existing versioned assets are refused.
`SOURCE_DATE_EPOCH` normalizes staged timestamps; signatures and notarization
still prevent a promise of byte-identical production rebuilds.

API-key authentication uses `--notary-key PATH --notary-key-id ID --notary-issuer ID`
instead of a profile, or `SCREENTIME_NOTARY_KEY_PATH`, `SCREENTIME_NOTARY_KEY_ID`,
and `SCREENTIME_NOTARY_ISSUER_ID`. Do not mix authentication methods.
`notarize-release-artifact.sh` only submits and waits; packaging handles stapling.
Omit production signing options for local ad-hoc packaging only.

Feed generation refuses unsigned, ad-hoc, unstapled, wrong-team, or
Gatekeeper-rejected inputs before accessing the update key. It checks the app's
feed URL and public key, generates archive and feed signatures with pinned,
checksum-verified Sparkle 2.9.5 tools, and verifies the signed feed.

## CI publication

Set up `radkawar/screentime-plus-plus` with GitHub Pages using Actions and a
protected `release-signing` Environment restricted to main and release tags.
Required secrets (same names as screenlogger):

- `DEVELOPER_ID_APPLICATION_P12` (base64) and `DEVELOPER_ID_APPLICATION_PASSWORD`
- `APP_STORE_CONNECT_API_KEY_P8`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`
- `SPARKLE_ED_PRIVATE_KEY`

Push main, wait for CI, then create and push the annotated version tag.
The Release workflow repeats tests and project-drift checks, imports the P12
into an ephemeral Keychain, requires the expected certificate fingerprint,
packages and notarizes, removes credentials, signs the feed, and publishes
using `gh release create`. It refuses to overwrite existing releases.
It publishes the versioned DMG and checksum plus
`ScreentimePlusPlus-latest-macos-universal.dmg` and its checksum.
Publication explicitly triggers Update Feed (GitHub token events alone do not).

Update Feed rejects drafts/prereleases, checks the immutable DMG URL and downloaded
checksum, and deploys the exact signed appcast to
<https://radkawar.github.io/screentime-plus-plus/appcast.xml>.
Keep offline backups of all signing credentials, especially the Sparkle private
key required for installed apps to trust future updates.
