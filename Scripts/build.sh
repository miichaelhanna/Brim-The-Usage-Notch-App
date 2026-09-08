#!/bin/bash
# Builds, signs and packages Brim.
#
#   bash Scripts/build.sh              app only, signed with whatever is available
#   DMG=1 bash Scripts/build.sh        also produce a .dmg
#   NOTARIZE=1 DMG=1 bash Scripts/build.sh   sign for release, notarise and staple
#
# Signing degrades on purpose: with a Developer ID certificate it signs for
# distribution, and without one it signs ad-hoc so a local build still runs. A
# contributor without a certificate must not be blocked from building.
#
# Notarisation needs a stored notarytool profile:
#   xcrun notarytool store-credentials usage-notch --apple-id <id> --team-id <team> --password <app-specific>
# Override the name with NOTARY_PROFILE, and the wait with NOTARY_TIMEOUT (default 30m).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
APP="dist/Brim.app"
# No space in the file name. GitHub rewrites a space in a release asset to a dot, so
# "Brim 1.0.0.dmg" is offered for download as "Brim.1.0.0.dmg".
DMG_PATH="dist/Brim-$VERSION.dmg"
NOTARIZE="${NOTARIZE:-0}"
DMG="${DMG:-0}"
# The keychain label the notarytool credential was stored under. It predates the
# app's rename to Brim; recreating it needs the app-specific password again, so the
# label simply stays what it is.
NOTARY_PROFILE="${NOTARY_PROFILE:-usage-notch}"
# How long to wait for Apple before giving up. Normal is a few minutes.
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-30m}"

# The in-app fallback version has to agree with the file, or `swift run` reports one
# number while the packaged app reports another.
if ! grep -q "\"$VERSION\"" Sources/Brim/AppVersion.swift; then
    echo "VERSION is $VERSION but AppVersion.swift says otherwise. Update both." >&2
    exit 1
fi

# Clear previous artefacts first. A failed run must never leave an older DMG behind
# looking like the current one. That is how an unsigned build gets uploaded by
# accident.
rm -f dist/*.dmg dist/notarize-*.zip

echo "==> Testing"
swift test

echo "==> Building $VERSION ($BUILD)"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Brim "$APP/Contents/MacOS/Brim"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "==> Icon"
if swift Scripts/icon.swift && iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    rm -rf dist/AppIcon.iconset
else
    # iconutil fails in some sandboxes. A previously generated icon is better than
    # failing the whole build over artwork.
    if [ -f Resources/AppIcon.icns ]; then
        cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
        echo "    reused Resources/AppIcon.icns"
    else
        echo "    no icon produced (continuing without one)"
    fi
fi

IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }' || true)"
fi

SIGN_ARGS=(--force --timestamp --options runtime)
if [ -n "$IDENTITY" ]; then
    echo "==> Signing as: $IDENTITY"
    SIGN_ARGS+=(--sign "$IDENTITY")
else
    echo "==> Signing ad-hoc (no Developer ID found; fine for local use, not for release)"
    # Ad-hoc signatures cannot carry a secure timestamp or the hardened runtime.
    SIGN_ARGS=(--force --sign -)
fi

xattr -cr "$APP"
# Synced folders can reattach FinderInfo between signing and verifying.
for attempt in 1 2 3; do
    xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
    if codesign "${SIGN_ARGS[@]}" "$APP"; then
        xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
        if codesign --verify --strict "$APP"; then break; fi
    fi
    if [ "$attempt" -eq 3 ]; then echo "Signing failed after 3 attempts." >&2; exit 1; fi
    xattr -cr "$APP"
done

# Submits one file and waits for Apple's verdict. Anything but Accepted is a failure,
# reported with Apple's own log so the reason is in the terminal rather than a portal.
notarise() {
    local file="$1" out id status
    echo "==> Notarising $(basename "$file")"
    # `--wait` alone polls forever. Apple occasionally loses a submission, which then
    # reads "In Progress" indefinitely; one such run sat for hours. The timeout turns
    # that into a failure that says what to do next.
    out="$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" \
        --wait --timeout "$NOTARY_TIMEOUT" 2>&1 | tee /dev/stderr)" || true
    id="$(printf '%s\n' "$out" | awk '/^ *id:/ { sub(/^ *id: */, ""); print; exit }')"
    status="$(printf '%s\n' "$out" | awk '/^ *status:/ { sub(/^ *status: */, ""); print }' | tail -1)"
    case "$status" in
        Accepted) ;;
        Invalid|Rejected)
            echo "Apple rejected $(basename "$file"). Its log:" >&2
            xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
            exit 1 ;;
        *)
            echo "Notarisation of $(basename "$file") did not finish within $NOTARY_TIMEOUT (last status: ${status:-unknown})." >&2
            echo "Resubmitting usually works when Apple has lost one. To check on this one:" >&2
            echo "    xcrun notarytool info ${id:-<id>} --keychain-profile $NOTARY_PROFILE" >&2
            exit 1 ;;
    esac
}

if [ "$NOTARIZE" = "1" ]; then
    if [ -z "$IDENTITY" ]; then
        echo "Cannot notarise an ad-hoc signed app. A Developer ID certificate is required." >&2
        exit 1
    fi
    ZIP="dist/notarize-$VERSION.zip"
    # Remove the upload archive whatever happens, including on failure.
    trap 'rm -f "$ZIP"' EXIT
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarise "$ZIP"
    xcrun stapler staple "$APP"
    # Prove it, rather than assuming the submission succeeded.
    spctl -a -vv "$APP"
fi

if [ "$DMG" = "1" ]; then
    echo "==> Packaging DMG"
    rm -f "$DMG_PATH"
    STAGE="$(mktemp -d)"
    ditto "$APP" "$STAGE/Brim.app"
    ln -s /Applications "$STAGE/Applications"

    # The install window. Without this the DMG opens as a bare Finder window with two
    # icons wherever Finder feels like putting them, which is the first thing anyone
    # sees of the app. Positions here must match Scripts/dmg-background.swift.
    mkdir -p "$STAGE/.background"
    if swift Scripts/dmg-background.swift \
       && tiffutil -cathidpicheck dist/dmg-background.png dist/dmg-background@2x.png \
            -out "$STAGE/.background/background.tiff" >/dev/null 2>&1; then
        LAYOUT=1
    else
        # A plain DMG still installs the app. Losing the artwork is not worth failing a
        # release build over.
        echo "    could not draw the backdrop; packaging without a layout" >&2
        LAYOUT=0
    fi
    rm -f dist/dmg-background.png dist/dmg-background@2x.png

    if [ "$LAYOUT" = "1" ]; then
        # Laying the window out means writing a .DS_Store, which only Finder can do, so
        # the image has to be mounted writable first and compressed afterwards.
        # A volume already called Brim would mount as "Brim 1" and the layout would
        # be applied to the wrong window, or to nothing.
        [ -d /Volumes/Brim ] && hdiutil detach /Volumes/Brim -force -quiet || true
        RW="$(mktemp -d)/rw.dmg"
        SIZE=$(( $(du -sm "$STAGE" | cut -f1) + 30 ))
        hdiutil create -quiet -srcfolder "$STAGE" -volname "Brim" -fs HFS+ \
            -format UDRW -size "${SIZE}m" -ov "$RW"
        MOUNT="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*$' | tail -1)"
        # Finder automation needs the operator's consent the first time. If it is refused
        # the DMG is still built, just without the layout.
        osascript >/dev/null 2>&1 <<'APPLESCRIPT' || echo "    Finder declined to lay the window out; packaging it plain" >&2
        tell application "Finder"
            tell disk "Brim"
                open
                set current view of container window to icon view
                set toolbar visible of container window to false
                set statusbar visible of container window to false
                set the bounds of container window to {200, 120, 840, 520}
                set viewOptions to the icon view options of container window
                set arrangement of viewOptions to not arranged
                set icon size of viewOptions to 100
                set text size of viewOptions to 12
                set background picture of viewOptions to file ".background:background.tiff"
                set position of item "Brim.app" of container window to {170, 175}
                set position of item "Applications" of container window to {470, 175}
                close
                open
                update without registering applications
                delay 2
            end tell
        end tell
APPLESCRIPT
        # Finder writes .DS_Store lazily. Detaching before it lands loses the layout.
        sync
        hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet
        hdiutil convert "$RW" -quiet -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
        rm -rf "$(dirname "$RW")"
    else
        hdiutil create -quiet -srcfolder "$STAGE" -volname "Brim" \
            -fs HFS+ -format UDZO -ov "$DMG_PATH"
    fi
    rm -rf "$STAGE"
    if [ "$NOTARIZE" = "1" ]; then
        # A ticket is issued per file, and the app's does not cover the disk image around
        # it: stapling a DMG that was never submitted fails with "could not find ticket".
        # So the DMG is signed and submitted too. Its contents already hold tickets, which
        # keeps this second pass short. Stapling it means a download that never unpacks
        # the app still passes Gatekeeper offline.
        codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
        notarise "$DMG_PATH"
        xcrun stapler staple "$DMG_PATH"
        spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
    fi
    echo "    $DMG_PATH"
fi

printf '\nBuilt %s (%s): %s\n' "$VERSION" "$BUILD" "$PWD/$APP"
if [ -z "$IDENTITY" ]; then
    printf 'Ad-hoc signed, so other Macs will warn. Set CODESIGN_IDENTITY for a release build.\n'
fi
