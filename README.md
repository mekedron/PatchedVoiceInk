# VoiceInk Patched Fork

Personal fork of [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) with trial removed and Sparkle auto-updates pointed to this fork.

## How it works

The `main` branch always contains exactly **1 commit ahead** of upstream — just the patched source code ready for release. No build scripts live on `main`.

This `patch` branch holds only the build script. It checks out `main`, resets to upstream, applies patches, builds, and returns here.

## Prerequisites

- **Xcode 26+**
- **`gh`** CLI — authenticated (`gh auth login`)
- **`op`** CLI — 1Password, signed in (`op signin`)
- **GitHub Pages** enabled on fork (Settings → Pages → Source: main, /docs)

The whisper.xcframework is auto-built on first run.

## Usage

```bash
# 1. Make sure you're on the patch branch
git checkout patch

# 2. Build and test
./patch.sh

# 3. Test the app
open ~/Downloads/VoiceInk.app

# 4. Publish release
./patch.sh --release
```

That's it. The script handles everything: syncing upstream, applying patches, building, signing, tagging, and creating the GitHub release.

## What the script does

### `./patch.sh` (build)

1. Fetches latest `upstream/main`
2. Switches to `main` and resets to upstream
3. Applies code patches (license bypass, Sparkle URLs)
4. Commits as a WIP on `main`
5. Builds app + DMG
6. Returns to `patch` branch

### `./patch.sh --release` (publish)

1. Switches to `main` (with WIP commit from build step)
2. Signs DMG with Sparkle key from 1Password
3. Updates `docs/appcast.xml`
4. Finalizes commit, tags as `v{VERSION}-{SHA}-patched`
5. Force pushes `main`, creates GitHub release with upstream notes
6. Returns to `patch` branch

## Patches applied

| File | Change |
|------|--------|
| `LicenseViewModel.swift` | Default state → `.licensed`, empty `startTrial()`, `canUseApp` → `true` |
| `TranscriptionPipeline.swift` | Remove `trialExpired` message prepended to transcriptions |
| `MetricsView.swift` | Remove trial/expired banner UI |
| `DashboardPromotionsSection.swift` | `shouldShowUpgradePromotion` → `false` |
| `LicenseManagementView.swift` | Replace license status with support message linking to tryvoiceink.com |
| `Info.plist` | `SUFeedURL` + `SUPublicEDKey` → fork values (2-line diff) |

## Release naming

Tags follow `v{VERSION}-{UPSTREAM_SHA}-patched`, e.g. `v1.72-a75ef6f-patched`, so you can always tell which upstream commit the build is based on.
