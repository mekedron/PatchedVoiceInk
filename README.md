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
- **`patch`** (default branch) holds the build script, workflow, supplemental Swift sources, and this README. It never changes during releases.

Every Monday at 10:00 UTC (or on manual trigger), GitHub Actions:
1. Checks if upstream has new commits since the last release
2. Applies patches, builds for Apple Silicon and Intel
3. Force pushes the patched source to `main`
4. Creates a GitHub release with both DMGs

## Repository layout

| Path | Purpose |
|------|---------|
| [`.github/workflows/build.yml`](.github/workflows/build.yml) | Canonical release pipeline — runs on cron + `workflow_dispatch`. Builds, signs, publishes both architectures. |
| [`patch.sh`](patch.sh) | Local script that mirrors what CI does, for development iteration and emergency manual releases. |
| [`patches/`](patches/) | Supplemental Swift sources injected into the upstream tree (currently `LaunchPermissionMonitor.swift`). Both `patch.sh` and `build.yml` copy from here, so it's the single source of truth for any net-new code. |
| [`docs/appcast.xml`](docs/appcast.xml) | Sparkle update feed served via GitHub Pages. Rewritten by CI on every release. |

## Local development

`patch.sh` is **not** required to ship a release — CI handles that. Use it for:

- **Quick iteration** — verify patches still apply against the latest upstream and the app actually compiles, before pushing changes that affect the workflow.
- **Emergency manual release** — fallback when CI is broken or you need to ship without waiting for the runner.

```bash
git checkout patch
./patch.sh            # apply patches, build, open ~/Downloads/VoiceInk.app
./patch.sh --release  # manual release path (rarely needed; CI normally does this)
```

Prerequisites:
- **Xcode 26+**
- **`gh`** CLI — only for `--release` (`gh auth login`)
- **`op`** CLI — only for `--release`, signs the DMG with the Sparkle key (`op signin`)

The whisper.xcframework is auto-built on first run and cached in `~/VoiceInk-Dependencies`.

### What `patch.sh` does

**`./patch.sh` (build)**

1. Fetches latest `upstream/main`
2. Switches to `main` and resets to upstream
3. Applies the same patches as CI (license bypass, Sparkle URLs, launch permission monitor)
4. Commits as a WIP on `main`
5. Builds app + DMG locally
6. Returns to `patch` branch

**`./patch.sh --release` (manual publish — CI does this normally)**

1. Switches to `main` (with WIP commit from build step)
2. Signs DMG with Sparkle key from 1Password
3. Updates `docs/appcast.xml`
4. Finalizes commit, tags as `v{VERSION}-{SHA}-patched`
5. Force pushes `main`, creates GitHub release with upstream notes
6. Returns to `patch` branch

> **Heads up:** the patch regexes live in **three copies across two files** — once in `patch.sh`, and twice in `.github/workflows/build.yml` (the `build` job applies them per-arch, the `publish` job re-applies them to push patched source to `main`). If you change a patch, mirror it in all three or CI and local builds will diverge. The supplemental Swift sources in `patches/` are the single source of truth and are copied by both.

## Patches applied

| File | Change |
|------|--------|
| Licensing — `LicenseViewModel.swift` + every build compiled with `LOCAL_BUILD` | Upstream's own `#if LOCAL_BUILD` branch forces `licenseState = .licensed` (and bypasses the license keychain / CloudKit). Our builds define `LOCAL_BUILD`, so the app always starts licensed. The `LicenseViewModel` regexes (`loadLicenseState`/`canUseApp` → licensed/`true`) are kept as defense-in-depth. |
| `Views/Dashboard/DashboardPromotionsSection.swift` | `shouldShowPromotions` → `false`, hiding **all** dashboard promo cards (the upgrade nag and the newer affiliate-program card) |
| `Views/LicenseManagementView.swift` | Inject a "Community Patched Build" support card at the top of the licensed `activeContent`, linking to tryvoiceink.com |
| `Info.plist` | `SUFeedURL` + `SUPublicEDKey` → fork values |
| `AppDelegate.swift` (modified) + `LaunchPermissionMonitor.swift` (new, copied from `patches/`) | Re-prompt for Microphone, Accessibility, and Screen Recording on every launch — the patched build's signature differs from the official one, so existing permission grants don't transfer |

The trial/expired banner and the `trialExpired` transcription notice are no longer patched out explicitly: in the forced-licensed state upstream already renders nothing for them, so those patches were dropped (the `TranscriptionPipeline` step now soft-skips). The cosmetic patches above **soft-fail** — if a future upstream refactor moves an anchor, the step prints a warning and continues instead of breaking the release.

## Release naming

Tags follow `v{VERSION}-{UPSTREAM_SHA}-patched`, e.g. `v1.72-a75ef6f-patched`, so you can always tell which upstream commit the build is based on.
