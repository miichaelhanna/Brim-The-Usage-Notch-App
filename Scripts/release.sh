#!/bin/bash
# Cuts a release: builds, signs, notarises, tags, and publishes to GitHub.
#
#   bash Scripts/release.sh                 release the version in VERSION
#   NOTES=path/to/notes.md bash Scripts/release.sh   with hand written notes
#
# Exists so the two easy things to forget cannot be forgotten: the tag, and the
# version-less DMG alias that the portfolio and any other download button rely on.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
REPO="${REPO:-miichaelhanna/Brim}"
NOTES="${NOTES:-}"

# Releasing a dirty tree ships something no commit describes, and the tag then
# points at code that is not what was built.
if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree is dirty. Commit or stash first." >&2
    exit 1
fi

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "$TAG already exists on $REPO. Bump VERSION and AppVersion.swift first." >&2
    exit 1
fi

NOTARIZE=1 DMG=1 bash Scripts/build.sh

DMG="dist/Brim-$VERSION.dmg"
[ -f "$DMG" ] || { echo "Expected $DMG. The build did not produce it." >&2; exit 1; }

# The alias. GitHub serves /releases/latest/download/<name>, so a version-less copy
# gives every download button one URL that never needs editing again. It is a byte
# for byte copy of the versioned DMG, so it carries the same signature and the same
# stapled notarisation ticket.
cp "$DMG" dist/Brim.dmg

git tag -a "$TAG" -m "Brim $VERSION"
git push origin "$TAG"

if [ -n "$NOTES" ]; then
    gh release create "$TAG" "$DMG" dist/Brim.dmg --repo "$REPO" \
        --title "Brim $VERSION" --notes-file "$NOTES" --latest
else
    gh release create "$TAG" "$DMG" dist/Brim.dmg --repo "$REPO" \
        --title "Brim $VERSION" --generate-notes --latest
fi

printf '\nReleased %s\n  https://github.com/%s/releases/tag/%s\n  https://github.com/%s/releases/latest/download/Brim.dmg\n' \
    "$TAG" "$REPO" "$TAG" "$REPO"
