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

# Signing identity: whichever Developer ID is in the keychain unless named.
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"

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
    <string>rdWqg6DxZAeugDCqV5pjjUUJck1xNni80UGLubN5wCI=</string>
</dict>
</plist>
PLIST

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Sign the app
if [ -z "${SIGN_IDENTITY}" ]; then
    echo "No Developer ID identity found. Set SIGN_IDENTITY, or import one." >&2
    exit 1
fi
echo "==> Signing app bundle as ${SIGN_IDENTITY}..."

# Sign Sparkle framework components (deep, inside-out)
codesign --force --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" \
    "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"

codesign --force --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" \
    "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"

codesign --force --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" \
    "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"

codesign --force --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" \
    "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"

codesign --force --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" \
    "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"

codesign --force --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" \
    "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

codesign --force --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" \
    "${APP_BUNDLE}"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

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
codesign --force --timestamp \
    --sign "${SIGN_IDENTITY}" \
    "build/${DMG_NAME}"

# Notarize
notarized=0
if [ "${SKIP_NOTARIZE}" = "1" ]; then
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
else
    echo "    DMG: build/${DMG_NAME} (signed, NOT notarized)"
fi
