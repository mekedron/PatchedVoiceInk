# VoiceInk Patched Fork

Personal fork of [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) with trial removed and Sparkle auto-updates pointed to this fork.

## Is this safe?

Yes. This fork is fully transparent:

- **Patch source code is open.** Every patch applied to the upstream code is defined in [`patch.sh`](patch.sh) on this branch and in the [GitHub Actions workflow](.github/workflows/build.yml). You can read exactly what is changed.
- **Builds happen only via GitHub Actions.** No local machines are involved in producing release binaries. The DMGs you download are built by GitHub-hosted runners from the public workflow — the build logs are visible to everyone.
- **`main` branch shows the patched source.** You can browse the [`main`](../../tree/main) branch to see the exact code that was compiled into the release, one commit ahead of upstream.

If you want to verify: compare [`main`](../../tree/main) against [upstream](https://github.com/Beingpax/VoiceInk) — the diff is only the patches listed below.

## How it works

- **`main`** branch contains exactly **1 commit ahead** of upstream — the patched source code, `docs/appcast.xml`, and nothing else. This is what gets built into releases.
- **`patch`** (default branch) holds the build script, workflow, and this README. It never changes during releases.

Every Monday at 10:00 UTC (or on manual trigger), GitHub Actions:
1. Checks if upstream has new commits since the last release
2. Applies patches, builds for Apple Silicon and Intel
3. Force pushes the patched source to `main`
4. Creates a GitHub release with both DMGs

## Local build (optional)

```bash
git checkout patch
./patch.sh            # build and test
./patch.sh --release  # sign and publish
```

Requires Xcode 26+, `gh` CLI, and `op` CLI (1Password) for Sparkle signing.

## Patches applied

| File | Change |
|------|--------|
| `LicenseViewModel.swift` | Default state -> `.licensed`, empty `startTrial()`, `canUseApp` -> `true` |
| `TranscriptionPipeline.swift` | Remove `trialExpired` message prepended to transcriptions |
| `MetricsView.swift` | Remove trial/expired banner UI |
| `DashboardPromotionsSection.swift` | `shouldShowUpgradePromotion` -> `false` |
| `LicenseManagementView.swift` | Replace license status with support message linking to tryvoiceink.com |
| `Info.plist` | `SUFeedURL` + `SUPublicEDKey` -> fork values |

## Release naming

Tags follow `v{VERSION}-{UPSTREAM_SHA}-patched`, e.g. `v1.72-a75ef6f-patched`, so you can always tell which upstream commit the build is based on.
