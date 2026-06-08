#!/usr/bin/env python3
"""
Apply the VoiceInk fork patches to an upstream source tree.

Single source of truth for every patch. Invoked identically by:
  - patch.sh                     — local build / manual release
  - .github/workflows/build.yml  — CI build job (per-arch) and publish job

Run it from the root of an upstream VoiceInk checkout (the directory that
contains `VoiceInk/`). Configuration comes from the environment:

  APPCAST_LINK         Sparkle feed URL written into Info.plist (SUFeedURL)
  SPARKLE_PUBLIC_KEY   Sparkle EdDSA public key written into Info.plist

The supplemental Swift source (LaunchPermissionMonitor.swift) is taken from
this script's own directory, so callers only need this `patches/` folder.

Functional patches (Sparkle URLs, permission monitor) fail loudly. Cosmetic
patches (promo hiding, support card) soft-fail with a warning so a future
upstream refactor cannot block a release — the licensing bypass itself rides
on upstream's own `#if LOCAL_BUILD` flag, which our builds always define.
"""
import os
import re
import shutil

ROOT = os.getcwd()
HERE = os.path.dirname(os.path.abspath(__file__))


def vpath(*parts):
    return os.path.join(ROOT, "VoiceInk", *parts)


def read(path):
    with open(path) as f:
        return f.read()


def write(path, src):
    with open(path, "w") as f:
        f.write(src)


def patch_license_view_model():
    """Force the licensed state.

    Upstream's own `#if LOCAL_BUILD` branch already sets `.licensed` for our
    builds; these substitutions keep the non-LOCAL_BUILD path licensed too and
    are kept as defense-in-depth. Each is a no-op if upstream drops the anchor.
    """
    path = vpath("Models", "LicenseViewModel.swift")
    src = read(path)
    src = re.sub(
        r'@Published private\(set\) var licenseState: LicenseState = \.trial\([^)]*\)[^\n]*',
        '@Published private(set) var licenseState: LicenseState = .licensed',
        src,
    )
    src = re.sub(r'func startTrial\(\) \{\n(.*?\n)*?    \}', 'func startTrial() {\n    }', src)
    src = re.sub(
        r'private func loadLicenseState\(\) \{\n(.*?\n)*?    \}',
        'private func loadLicenseState() {\n        licenseState = .licensed\n    }',
        src,
    )
    src = re.sub(r'var canUseApp: Bool \{\n(.*?\n)*?    \}', 'var canUseApp: Bool {\n        true\n    }', src)
    src = re.sub(r'licenseState = \.trial\(daysRemaining: trialPeriodDays\)[^\n]*', 'licenseState = .licensed', src)
    write(path, src)
    print("  Patched LicenseViewModel.swift")


def patch_transcription_pipeline():
    """Strip a `trialExpired` notice prepended to transcriptions, if present.

    Upstream no longer does this; the step soft-skips when no match is found.
    """
    target = None
    for base, _dirs, files in os.walk(os.path.join(ROOT, "VoiceInk")):
        for fn in sorted(files):
            if not fn.endswith(".swift"):
                continue
            fp = os.path.join(base, fn)
            if re.search(r'trialExpired.*licenseViewModel', read(fp)):
                target = fp
                break
        if target:
            break
    if target:
        src = re.sub(
            r'\n\s*if case \.trialExpired = licenseViewModel\.licenseState \{\n.*?\}\n',
            '\n',
            read(target),
            flags=re.DOTALL,
        )
        write(target, src)
        print(f"  Patched {os.path.relpath(target, ROOT)}")
    else:
        print("  (no trialExpired block found — skipping)")


def patch_dashboard_promotions():
    """Hide every dashboard promo card (upgrade nag + affiliate program)."""
    path = vpath("Views", "Dashboard", "DashboardPromotionsSection.swift")
    if not os.path.exists(path):
        print("  WARNING: DashboardPromotionsSection.swift not found — skipping")
        return
    src, n = re.subn(
        r'(private var shouldShowPromotions: Bool \{\n).*?(\n    \})',
        r'\1        false\2',
        read(path),
        count=1,
        flags=re.DOTALL,
    )
    write(path, src)
    print("  Patched DashboardPromotionsSection.swift" if n else "  WARNING: shouldShowPromotions anchor not found")


def patch_license_management_view():
    """Inject a community-build support card atop the licensed `activeContent`."""
    path = vpath("Views", "LicenseManagementView.swift")
    if not os.path.exists(path):
        print("  WARNING: LicenseManagementView.swift not found — skipping")
        return
    src = read(path)
    anchor = "    private var activeContent: some View {\n"
    vstack = "        VStack(spacing: 14) {\n            activeLicenseCard"
    card = (
        '    private var patchedBuildSupportCard: some View {\n'
        '        VStack(alignment: .leading, spacing: 16) {\n'
        '            HStack(spacing: 10) {\n'
        '                Image(systemName: "heart.circle.fill")\n'
        '                    .font(.system(size: 22))\n'
        '                    .foregroundStyle(.pink)\n'
        '                Text("Community Patched Build")\n'
        '                    .font(.headline)\n'
        '                Spacer()\n'
        '            }\n'
        '\n'
        '            Text("You are using an unofficial, community-patched build of VoiceInk, crafted by a solo indie developer who pours their heart into making voice-to-text effortless.")\n'
        '                .font(.subheadline)\n'
        '                .foregroundStyle(.secondary)\n'
        '                .fixedSize(horizontal: false, vertical: true)\n'
        '\n'
        '            Text("If VoiceInk is part of your daily workflow, consider buying a license to support its continued development.")\n'
        '                .font(.subheadline)\n'
        '                .foregroundStyle(.secondary)\n'
        '                .fixedSize(horizontal: false, vertical: true)\n'
        '\n'
        '            Button {\n'
        '                openURL("https://tryvoiceink.com/")\n'
        '            } label: {\n'
        '                Label("Get VoiceInk — Support the Developer", systemImage: "cart.fill")\n'
        '                    .frame(maxWidth: .infinity)\n'
        '                    .padding(.vertical, 8)\n'
        '            }\n'
        '            .buttonStyle(.borderedProminent)\n'
        '        }\n'
        '        .padding(22)\n'
        '        .frame(maxWidth: .infinity, alignment: .leading)\n'
        '        .background(AppMaterialCardBackground(cornerRadius: 14))\n'
        '    }\n'
        '\n'
    )
    if "patchedBuildSupportCard" in src:
        print("  LicenseManagementView.swift already patched — skipping")
        return
    if anchor in src and vstack in src:
        src = src.replace(anchor, card + anchor, 1)
        src = src.replace(
            vstack,
            "        VStack(spacing: 14) {\n            patchedBuildSupportCard\n            activeLicenseCard",
            1,
        )
        write(path, src)
        print("  Patched LicenseManagementView.swift (support card injected)")
    else:
        print("  WARNING: LicenseManagementView anchors not found — support card NOT injected")


def patch_info_plist():
    """Point Sparkle at the fork's appcast feed and public key."""
    url = os.environ.get("APPCAST_LINK", "")
    key = os.environ.get("SPARKLE_PUBLIC_KEY", "")
    path = vpath("Info.plist")
    src = read(path)
    src = re.sub(r'(<key>SUFeedURL</key>\s*<string>)[^<]*(</string>)', r'\g<1>' + url + r'\2', src)
    src = re.sub(r'(<key>SUPublicEDKey</key>\s*<string>)[^<]*(</string>)', r'\g<1>' + key + r'\2', src)
    write(path, src)
    print(f"  Patched Info.plist -> {url}")


def patch_launch_permission_monitor():
    """Drop in LaunchPermissionMonitor.swift and bootstrap it from AppDelegate.

    The patched build's signature differs from the official one, so existing
    permission grants don't transfer — we re-prompt on every launch.
    """
    supplement = os.path.join(HERE, "LaunchPermissionMonitor.swift")
    shutil.copy(supplement, vpath("LaunchPermissionMonitor.swift"))
    print("  Copied LaunchPermissionMonitor.swift")

    path = vpath("AppDelegate.swift")
    src, n = re.subn(
        r'(menuBarManager\?\.applyActivationPolicy\(\))',
        r'\1\n        LaunchPermissionMonitor.shared.bootstrap()',
        read(path),
        count=1,
    )
    assert n == 1, "AppDelegate.swift anchor not found"
    write(path, src)
    print("  Patched AppDelegate.swift")


def main():
    print("==> Applying VoiceInk fork patches...")
    patch_license_view_model()
    patch_transcription_pipeline()
    patch_dashboard_promotions()
    patch_license_management_view()
    patch_info_plist()
    patch_launch_permission_monitor()
    print("==> All patches applied")


if __name__ == "__main__":
    main()
