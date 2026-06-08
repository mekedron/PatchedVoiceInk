#!/bin/bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
UPSTREAM_URL="https://github.com/Beingpax/VoiceInk.git"
GITHUB_REPO="mekedron/VoiceInk"
OP_ITEM="VoiceInk Sparkle Signing Key"
OP_VAULT="Personal"
SPARKLE_PUBLIC_KEY="22HdaJksDsRyOwfyMqARsF0on0MXQdfmCSeGTk+EaCU="
APPCAST_LINK="https://mekedron.github.io/VoiceInk/appcast.xml"
LOCAL_DERIVED_DATA=".local-build"
SPARKLE_BIN="$LOCAL_DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"
DEPS_DIR="$HOME/VoiceInk-Dependencies"
WHISPER_DIR="$DEPS_DIR/whisper.cpp"
FRAMEWORK_PATH="$WHISPER_DIR/build-apple/whisper.xcframework"

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

# ── Parse arguments ───────────────────────────────────────────────────────────
ACTION="${1:-build}"

if [ "$ACTION" != "build" ] && [ "$ACTION" != "--release" ]; then
    echo "Usage:"
    echo "  ./patch.sh            Sync, patch, build, and open app for testing"
    echo "  ./patch.sh --release  Sign, commit, push, and create GitHub release"
    echo ""
    echo "Run without arguments first, test the app, then run with --release."
    exit 0
fi

# ── Branch guard ──────────────────────────────────────────────────────────────
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
if [ "$CURRENT_BRANCH" != "patch" ]; then
    echo "Error: Must run from the 'patch' branch. Current branch: $CURRENT_BRANCH"
    echo "  Run: git checkout patch"
    exit 1
fi

# ── EXIT trap: return to patch branch on exit ─────────────────────────────────
SHOULD_RETURN=false
cleanup() {
    local rc=$?
    trap - EXIT
    if [ "$SHOULD_RETURN" = true ] && [ "$(git symbolic-ref --short HEAD 2>/dev/null)" != "patch" ]; then
        git checkout patch 2>/dev/null || true
    fi
    exit $rc
}
trap cleanup EXIT

# ══════════════════════════════════════════════════════════════════════════════
#  BUILD MODE: sync upstream, apply patches, build app + DMG
# ══════════════════════════════════════════════════════════════════════════════
if [ "$ACTION" = "build" ]; then

# ── Preflight checks ──────────────────────────────────────────────────────────
echo "==> Checking prerequisites..."
for cmd in git xcodebuild python3 hdiutil op; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: $cmd not found"; exit 1; }
done
op account get >/dev/null 2>&1 || { echo "Error: op not signed in. Run: op signin"; exit 1; }
echo "Prerequisites OK"

# ── Sync with upstream ────────────────────────────────────────────────────────
echo ""
echo "==> Syncing with upstream..."
if ! git remote get-url upstream &>/dev/null; then
    git remote add upstream "$UPSTREAM_URL"
fi
git fetch upstream

# ── Save appcast from main (if it exists) ─────────────────────────────────────
STASH_DIR=$(mktemp -d)
git show main:docs/appcast.xml > "$STASH_DIR/appcast.xml" 2>/dev/null || true

# Stash the patch toolkit from the patch branch working tree, since the next
# step checks out `main` (where these files don't exist). The branch guard above
# ensures we're on `patch` with these files present. `apply.py` is the single
# source of truth for every patch — see also .github/workflows/build.yml.
mkdir -p "$STASH_DIR/patches"
cp patches/apply.py patches/LaunchPermissionMonitor.swift "$STASH_DIR/patches/"

# ── Switch to main and reset to upstream ──────────────────────────────────────
echo ""
echo "==> Resetting main to upstream/main..."
SHOULD_RETURN=true
git checkout main
git reset --hard upstream/main

# ── Capture upstream info ─────────────────────────────────────────────────────
UPSTREAM_SHA_SHORT=$(git rev-parse --short HEAD)
UPSTREAM_SHA=$(git rev-parse HEAD)

# ── Read version ──────────────────────────────────────────────────────────────
VERSION=$(grep 'MARKETING_VERSION' VoiceInk.xcodeproj/project.pbxproj \
    | head -1 | grep -oE '[0-9]+\.[0-9]+[0-9.]*')
TAG="v${VERSION}-${UPSTREAM_SHA_SHORT}-patched"
DMG_NAME="VoiceInk-${VERSION}.dmg"
echo "==> Version: $VERSION  Tag: $TAG  Based on: $UPSTREAM_SHA_SHORT"

# ── Apply patches (single source of truth: patches/apply.py) ──────────────────
# apply.py was stashed alongside LaunchPermissionMonitor.swift before we checked
# out `main`; it runs against the current working tree (the upstream source).
echo ""
APPCAST_LINK="$APPCAST_LINK" SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" \
    python3 "$STASH_DIR/patches/apply.py"

# ── Restore docs ──────────────────────────────────────────────────────────────
mkdir -p docs
touch docs/.nojekyll
if [ -s "$STASH_DIR/appcast.xml" ]; then
    cp "$STASH_DIR/appcast.xml" docs/appcast.xml
else
    cat > docs/appcast.xml << 'APPCAST'
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
    <channel>
        <title>VoiceInk</title>
        <link>https://mekedron.github.io/VoiceInk/appcast.xml</link>
        <description>VoiceInk Updates</description>
        <language>en</language>
    </channel>
</rss>
APPCAST
fi
rm -rf "$STASH_DIR"

# ── Commit patches (WIP — finalized on release) ──────────────────────────────
echo ""
echo "==> Committing patches..."
git add -A
git reset -- '*.dmg' .local-build/ 2>/dev/null || true
git commit -m "WIP: patched v${VERSION} based on upstream ${UPSTREAM_SHA_SHORT}"

# ── Build whisper framework ───────────────────────────────────────────────────
echo ""
if [ ! -d "$FRAMEWORK_PATH" ]; then
    echo "==> Building whisper.xcframework..."
    mkdir -p "$DEPS_DIR"
    if [ ! -d "$WHISPER_DIR" ]; then
        git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
    fi
    (cd "$WHISPER_DIR" && ./build-xcframework.sh)
else
    echo "==> whisper.xcframework already built, skipping"
fi

# ── Build app ─────────────────────────────────────────────────────────────────
echo ""
echo "==> Resolving packages..."
rm -rf "$LOCAL_DERIVED_DATA"
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
    -derivedDataPath "$LOCAL_DERIVED_DATA" \
    -xcconfig LocalBuild.xcconfig \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="" \
    CODE_SIGN_ENTITLEMENTS="$ROOT/VoiceInk/VoiceInk.local.entitlements" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
    -resolvePackageDependencies

FLUID_PKG="$LOCAL_DERIVED_DATA/SourcePackages/checkouts/FluidAudio/Package.swift"
if [ -f "$FLUID_PKG" ] && ! grep -q 'swiftLanguageMode' "$FLUID_PKG"; then
    echo "==> Patching FluidAudio for Swift 5 language mode..."
    chmod u+w "$FLUID_PKG"
    python3 - "$FLUID_PKG" << 'PYEOF'
import sys
p = sys.argv[1]
with open(p) as f:
    src = f.read()
old = '"Frameworks"\n            ]'
new = '"Frameworks"\n            ],\n            swiftSettings: [\n                .swiftLanguageMode(.v5)\n            ]'
result = src.replace(old, new, 1)
if result != src:
    with open(p, "w") as f:
        f.write(result)
PYEOF
fi

echo "==> Building VoiceInk..."
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
    -derivedDataPath "$LOCAL_DERIVED_DATA" \
    -xcconfig LocalBuild.xcconfig \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="" \
    CODE_SIGN_ENTITLEMENTS="$ROOT/VoiceInk/VoiceInk.local.entitlements" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
    -skipPackagePluginValidation \
    build

APP_PATH="$LOCAL_DERIVED_DATA/Build/Products/Debug/VoiceInk.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Build failed — VoiceInk.app not found"
    exit 1
fi

rm -rf "$HOME/Downloads/VoiceInk.app"
ditto "$APP_PATH" "$HOME/Downloads/VoiceInk.app"
xattr -cr "$HOME/Downloads/VoiceInk.app"

# ── Create DMG ────────────────────────────────────────────────────────────────
echo ""
echo "==> Creating DMG..."
rm -f "$DMG_NAME"
DMG_DIR=$(mktemp -d)
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"
hdiutil create -volname "VoiceInk" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_NAME"
rm -rf "$DMG_DIR"

# ── Done (build mode) ────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Build complete! Test the app:"
echo "============================================"
echo ""
echo "  open ~/Downloads/VoiceInk.app"
echo ""
echo "  When ready to publish:"
echo "  ./patch.sh --release"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
#  RELEASE MODE: sign, commit, push, create GitHub release
# ══════════════════════════════════════════════════════════════════════════════
elif [ "$ACTION" = "--release" ]; then

# ── Preflight ─────────────────────────────────────────────────────────────────
for cmd in gh op; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: $cmd not found"; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "Error: gh not authenticated. Run: gh auth login"; exit 1; }
op account get >/dev/null 2>&1 || { echo "Error: op not signed in. Run: op signin"; exit 1; }

# ── Verify WIP commit on main ────────────────────────────────────────────────
WIP_MSG=$(git log -1 --format=%s main 2>/dev/null || echo "")
if [[ "$WIP_MSG" != WIP:* ]]; then
    echo "Error: No WIP build commit found on main."
    echo "  Run ./patch.sh first to build."
    exit 1
fi

# ── Switch to main ────────────────────────────────────────────────────────────
SHOULD_RETURN=true
git checkout main

# ── Read version and upstream info ────────────────────────────────────────────
UPSTREAM_SHA=$(git rev-parse HEAD~1)
UPSTREAM_SHA_SHORT=$(git rev-parse --short HEAD~1)
VERSION=$(grep 'MARKETING_VERSION' VoiceInk.xcodeproj/project.pbxproj \
    | head -1 | grep -oE '[0-9]+\.[0-9]+[0-9.]*')
TAG="v${VERSION}-${UPSTREAM_SHA_SHORT}-patched"
DMG_NAME="VoiceInk-${VERSION}.dmg"
APP_PATH="$LOCAL_DERIVED_DATA/Build/Products/Debug/VoiceInk.app"

if [ ! -f "$DMG_NAME" ]; then
    echo "Error: $DMG_NAME not found. Run ./patch.sh first."
    exit 1
fi
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Built app not found. Run ./patch.sh first."
    exit 1
fi

echo "==> Releasing $TAG"

# ── Sign DMG ──────────────────────────────────────────────────────────────────
echo ""
echo "==> Signing DMG with Sparkle key from 1Password..."
SIGN_OUTPUT=$(op item get "$OP_ITEM" --vault "$OP_VAULT" \
    --fields "Section_sparkle.private_key" --reveal \
    | "$SPARKLE_BIN/sign_update" --ed-key-file - "$DMG_NAME")

ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep 'edSignature=' | sed 's/.*edSignature="\([^"]*\)".*/\1/')
DMG_LENGTH=$(echo "$SIGN_OUTPUT" | grep 'length=' | sed 's/.*length="\([^"]*\)".*/\1/')
echo "  Signature: $ED_SIGNATURE"
echo "  Length: $DMG_LENGTH"

# ── Update appcast ────────────────────────────────────────────────────────────
echo ""
echo "==> Updating appcast.xml..."
BUILD_NUMBER=$(defaults read "$PWD/$APP_PATH/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "1")
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$TAG/$DMG_NAME"
PUB_DATE=$(date -R)

python3 - "$TAG" "$PUB_DATE" "$DOWNLOAD_URL" "$BUILD_NUMBER" "$VERSION" "$ED_SIGNATURE" "$DMG_LENGTH" << 'PYEOF'
import xml.etree.ElementTree as ET
import sys

tag, pub_date, url, build, ver, sig, length = sys.argv[1:8]

ET.register_namespace('sparkle', 'http://www.andymatuschak.org/xml-namespaces/sparkle')
ET.register_namespace('dc', 'http://purl.org/dc/elements/1.1/')

tree = ET.parse('docs/appcast.xml')
ch = tree.find('channel')

for old in ch.findall('item'):
    ch.remove(old)

item = ET.SubElement(ch, 'item')
ET.SubElement(item, 'title').text = f'Version {tag}'
ET.SubElement(item, 'pubDate').text = pub_date
enc = ET.SubElement(item, 'enclosure')
enc.set('url', url)
enc.set('{http://www.andymatuschak.org/xml-namespaces/sparkle}version', build)
enc.set('{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString', f'{ver}-patched')
enc.set('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature', sig)
enc.set('length', length)
enc.set('type', 'application/octet-stream')
ET.indent(tree, space='    ')
tree.write('docs/appcast.xml', xml_declaration=True, encoding='unicode')
print("  Appcast updated")
PYEOF

# ── Amend WIP commit with final message + appcast ────────────────────────────
echo ""
echo "==> Finalizing commit..."
git add -A
git reset -- '*.dmg' .local-build/ 2>/dev/null || true
git commit --amend -m "feat: patched v${VERSION} based on upstream ${UPSTREAM_SHA_SHORT}"

# ── Tag and force push ────────────────────────────────────────────────────────
git tag -d "$TAG" 2>/dev/null || true
git tag "$TAG"

echo "==> Force pushing to origin..."
git push origin main --force
git push origin "$TAG" --force

# ── Gather release notes ──────────────────────────────────────────────────────
echo ""
echo "==> Gathering release notes..."

# Find the latest version tag reachable from upstream base
LATEST_TAG=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo "")

# Fetch upstream release notes for that tag
UPSTREAM_NOTES=""
if [ -n "$LATEST_TAG" ]; then
    UPSTREAM_NOTES=$(gh release view "$LATEST_TAG" --repo Beingpax/VoiceInk --json body -q .body 2>/dev/null || echo "")
fi

# Commits on main after the latest tag (unreleased upstream changes)
COMMIT_LOG=""
if [ -n "$LATEST_TAG" ]; then
    COMMIT_LOG=$(git log --format="- %s (\`%h\`)" "${LATEST_TAG}..HEAD~1" 2>/dev/null || echo "")
fi

NOTES_FILE=$(mktemp)
cat > "$NOTES_FILE" << NOTESEOF
Patched release based on [upstream/main@${UPSTREAM_SHA_SHORT}](https://github.com/Beingpax/VoiceInk/commit/$UPSTREAM_SHA).

## Fork changes
- Trial expiration removed — app always starts in licensed state
- Sparkle auto-updates pointed to this fork
NOTESEOF

if [ -n "$UPSTREAM_NOTES" ]; then
    cat >> "$NOTES_FILE" << NOTESEOF

---

## Upstream release notes (${LATEST_TAG})

${UPSTREAM_NOTES}
NOTESEOF
fi

if [ -n "$COMMIT_LOG" ]; then
    cat >> "$NOTES_FILE" << NOTESEOF

## Unreleased upstream commits (since ${LATEST_TAG})

${COMMIT_LOG}
NOTESEOF
fi

# ── GitHub release ────────────────────────────────────────────────────────────
echo ""
echo "==> Creating GitHub release $TAG..."

gh release delete "$TAG" --repo "$GITHUB_REPO" --yes 2>/dev/null || true

gh release create "$TAG" "$DMG_NAME" \
    --repo "$GITHUB_REPO" \
    --title "VoiceInk $TAG" \
    --notes-file "$NOTES_FILE"
rm -f "$NOTES_FILE"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Done! VoiceInk $TAG released"
echo "============================================"
echo ""
echo "  Release:  https://github.com/$GITHUB_REPO/releases/tag/$TAG"
echo "  Appcast:  $APPCAST_LINK"
echo ""

fi
