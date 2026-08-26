#!/bin/bash
set -euo pipefail

# Everything here can be overridden from the environment, so the same script
# builds a local release and a CI one. The version comes from project.yml,
# which is the single place it is written down.
APP_NAME="${APP_NAME:-ClaudePulse}"
BUNDLE_ID="${BUNDLE_ID:-com.ccani.app}"
VERSION="${VERSION:-$(awk -F'"' '/MARKETING_VERSION/ { print $2; exit }' project.yml)}"

# The feed the built app checks for updates: the repository it was built from,
# so a fork's builds do not point users at someone else's releases. In CI that
# is what GitHub says it is; locally it is whatever `origin` points at.
default_repo="$(git remote get-url origin 2>/dev/null \
    | sed -E 's#(git@|https://)github\.com[:/]##; s#\.git$##')"
FEED_REPO="${FEED_REPO:-${GITHUB_REPOSITORY:-${default_repo:-tzangms/ClaudePulse}}}"
FEED_URL="${FEED_URL:-https://raw.githubusercontent.com/${FEED_REPO}/main/appcast.xml}"

# The public half of the Sparkle signing key, so the built app only accepts
# updates signed with the matching private key. project.yml holds the one the
# Xcode build uses; reading it here keeps the two from drifting apart.
PUBLIC_ED_KEY="${PUBLIC_ED_KEY:-$(awk '/SUPublicEDKey:/ { print $2; exit }' project.yml)}"

# Signing identity: whichever Developer ID is in the keychain unless named.
# Without one the build can still finish ad-hoc — Apple silicon refuses to run
# an unsigned binary at all, so "unsigned" in practice means signed by nobody.
# Gatekeeper will not accept it, which is why it takes saying so out loud.
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
ALLOW_ADHOC_SIGN="${ALLOW_ADHOC_SIGN:-0}"

# Notarization takes either a stored keychain profile (local) or an Apple ID
# with an app-specific password (CI). Without either it is skipped, and the
# build says so rather than pretending it shipped something notarized.
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

BUILD_DIR=".build/release"
APP_BUNDLE="build/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_DIR="build/dmg"

echo "==> Building release binary..."
swift build -c release

echo "==> Creating app bundle..."
rm -rf build
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary and fix rpath for bundled frameworks
cp "${BUILD_DIR}/ccpulse" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
install_name_tool -add_rpath @executable_path/../Frameworks "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

# Copy icon
cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

# Copy Sparkle framework
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
cp -R "${BUILD_DIR}/Sparkle.framework" "${APP_BUNDLE}/Contents/Frameworks/"

# Create Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>NSAppleEventsUsageDescription</key>
    <string>ClaudePulse needs access to send Apple Events to open Terminal.</string>
    <key>SUFeedURL</key>
    <string>${FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${PUBLIC_ED_KEY}</string>
</dict>
</plist>
PLIST

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Sign the app
adhoc=0
if [ "${SIGN_IDENTITY}" = "-" ] || [ -z "${SIGN_IDENTITY}" ]; then
    if [ "${SIGN_IDENTITY}" = "-" ] || [ "${ALLOW_ADHOC_SIGN}" = "1" ]; then
        SIGN_IDENTITY="-"
        adhoc=1
        echo "==> No Developer ID — signing ad-hoc. This build cannot be notarized" >&2
        echo "    and Gatekeeper will refuse it until the user clears the quarantine." >&2
    else
        echo "No Developer ID identity found. Set SIGN_IDENTITY, import one, or" >&2
        echo "pass ALLOW_ADHOC_SIGN=1 to build something unsigned on purpose." >&2
        exit 1
    fi
else
    echo "==> Signing app bundle as ${SIGN_IDENTITY}..."
fi

# A trusted timestamp needs a real identity; an ad-hoc signature cannot have one.
sign() {
    if [ "${adhoc}" = "1" ]; then
        codesign --force --options runtime --sign - "$1"
    else
        codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "$1"
    fi
}

# Sign Sparkle framework components (deep, inside-out)
sign "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
sign "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
sign "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
sign "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
sign "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
sign "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
sign "${APP_BUNDLE}"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
if [ "${adhoc}" = "0" ]; then
    # Only a real identity can satisfy Gatekeeper, so only then is it worth asking.
    spctl --assess --type execute --verbose=2 "${APP_BUNDLE}" || \
        echo "==> Gatekeeper is not happy with this signature yet (notarization pending)." >&2
fi

# Create DMG
echo "==> Creating DMG..."
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"
cp -R "${APP_BUNDLE}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "build/${DMG_NAME}"

rm -rf "${DMG_DIR}"

# Sign the DMG
echo "==> Signing DMG..."
if [ "${adhoc}" = "1" ]; then
    codesign --force --sign - "build/${DMG_NAME}"
else
    codesign --force --timestamp --sign "${SIGN_IDENTITY}" "build/${DMG_NAME}"
fi

# Notarize
notarized=0
if [ "${adhoc}" = "1" ]; then
    echo "==> Not notarizing: an ad-hoc signature cannot be notarized."
elif [ "${SKIP_NOTARIZE}" = "1" ]; then
    echo "==> Skipping notarization (SKIP_NOTARIZE=1)."
elif [ -n "${NOTARY_PROFILE}" ]; then
    echo "==> Submitting for notarization (keychain profile ${NOTARY_PROFILE})..."
    xcrun notarytool submit "build/${DMG_NAME}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait
    notarized=1
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    echo "==> Submitting for notarization (Apple ID ${APPLE_ID})..."
    xcrun notarytool submit "build/${DMG_NAME}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --password "${APPLE_APP_PASSWORD}" \
        --wait
    notarized=1
else
    echo "==> No notarization credentials — set NOTARY_PROFILE, or APPLE_ID," >&2
    echo "    APPLE_TEAM_ID and APPLE_APP_PASSWORD, or SKIP_NOTARIZE=1." >&2
    exit 1
fi

if [ "${notarized}" = "1" ]; then
    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "build/${DMG_NAME}"
    xcrun stapler validate "build/${DMG_NAME}"
fi

echo ""
echo "==> Done!"
echo "    App: ${APP_BUNDLE}"
if [ "${notarized}" = "1" ]; then
    echo "    DMG: build/${DMG_NAME} (signed + notarized)"
elif [ "${adhoc}" = "1" ]; then
    echo "    DMG: build/${DMG_NAME} (ad-hoc signed, NOT notarized)"
else
    echo "    DMG: build/${DMG_NAME} (signed, NOT notarized)"
fi
