#!/bin/zsh
#
# build-app.sh — build Prizm.app from source without Xcode's build system.
#
# Why this exists: `xcodebuild` resolves SwiftPM packages by re-entering
# `sandbox-exec`, which fails inside an already-sandboxed process
# ("sandbox-exec: sandbox_apply: Operation not permitted"). SwiftPM's own CLI
# supports `--disable-sandbox`, so we compile with `swift build` and hand-assemble
# the .app bundle. The Xcode project remains the source of truth for release builds.
#
# Usage:  ./build-app.sh            # debug build
#         ./build-app.sh release    # release build
#
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/Prizm.app"
ENT="$ROOT/dist/Prizm.local.entitlements"

cd "$ROOT"

echo "==> Building ($CONFIG) with SwiftPM (sandbox disabled)"
/usr/bin/swift build --disable-sandbox -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/Prizm"
[[ -f "$BIN" ]] || { echo "error: binary not found at $BIN"; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Prizm"
cp "$ROOT/Prizm/Resources/eff-large-wordlist.txt" "$APP/Contents/Resources/"

# Localizations. `Bundle.main` looks for `Localizable.strings` inside
# Contents/Resources/<lang>.lproj, which is exactly where Xcode would put them.
for lproj in "$ROOT"/Prizm/Resources/*.lproj; do
  [[ -d "$lproj" ]] || continue
  cp -R "$lproj" "$APP/Contents/Resources/"
done

printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>Prizm</string>
	<key>CFBundleIconFile</key><string>Prizm_V2</string>
	<key>CFBundleIconName</key><string>Prizm_V2</string>
	<key>CFBundleIdentifier</key><string>com.prizm</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>Prizm</string>
	<key>CFBundleDisplayName</key><string>Prizm</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.4.3</string>
	<key>CFBundleVersion</key><string>12</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSSupportsAutomaticTermination</key><true/>
	<key>NSSupportsSuddenTermination</key><true/>
	<key>NSFaceIDUsageDescription</key><string>Prizm uses Touch ID to unlock your vault.</string>
</dict>
</plist>
PLIST

# App icon (optional — skipped silently if actool cannot compile the .icon bundle)
mkdir -p "$APP/Contents/Resources"
if /usr/bin/xcrun actool --version >/dev/null 2>&1; then
  /usr/bin/xcrun actool \
      --compile "$APP/Contents/Resources" \
      --app-icon Prizm_V2 \
      --platform macosx \
      --minimum-deployment-target 26.0 \
      --target-device mac \
      --output-partial-info-plist /tmp/prizm_actool.plist \
      "$ROOT/Prizm/Prizm/Prizm_V2.icon" >/dev/null 2>&1 \
    && echo "==> App icon compiled" \
    || echo "==> App icon skipped (actool could not compile Prizm_V2.icon)"
fi

echo "==> Ad-hoc signing"
# Local builds run WITHOUT the App Sandbox by default.
#
# Rationale: a sandboxed bundle is supposed to reach the keychain through an
# access group (`keychain-access-groups`, derived from a real Team ID). An ad-hoc
# signed bundle has no Team ID, and `keychain-access-groups` is a *restricted*
# entitlement — applying it to an ad-hoc binary makes AMFI SIGKILL the process at
# launch. A sandboxed, teamless build therefore has no usable access group and is
# permanently stuck on the legacy login keychain, where access is granted per
# binary. Dropping the sandbox gives the same legacy keychain with one less
# variable in the way, which is what we want for a local test build.
#
# NOTE: the sandbox is NOT what causes the "Prizm wants to use confidential
# information stored in ..." prompt — that was tested and disproved. The prompt
# comes from *stale keychain items*: items created by an earlier build may not be
# recognised as owned by the current binary, so touching them demands the login
# keychain password. It does not reproduce on every rebuild (a rebuild that only
# changes Swift sources has been observed to start cleanly), but when it does
# happen the app cannot get past the dialog. Run ./reset-keychain.sh to clear the
# items and let the app recreate its own.
#
# Set PRIZM_SANDBOX=1 to restore the upstream (sandboxed) configuration.
SANDBOX="${PRIZM_SANDBOX:-0}"
if [[ "$SANDBOX" == "1" ]]; then
  echo "    (sandbox ENABLED — keychain prompts are expected on teamless builds)"
  cat > "$ENT" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key><true/>
	<key>com.apple.security.network.client</key><true/>
	<key>com.apple.security.files.user-selected.read-write</key><true/>
</dict>
</plist>
ENTITLEMENTS
else
  echo "    (sandbox DISABLED for local testing)"
  cat > "$ENT" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.network.client</key><true/>
</dict>
</plist>
ENTITLEMENTS
fi

codesign --force --sign - --entitlements "$ENT" "$APP"

echo "==> Done: $APP"
echo "    Launch with:  open \"$APP\""
echo ""
echo "    Reminder: this rebuild changed the code signature. If the app now shows a"
echo "    \"wants to use confidential information stored in \\\"com.prizm\\\"\" dialog,"
echo "    run ./reset-keychain.sh and relaunch (you will need to sign in again)."
