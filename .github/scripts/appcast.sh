#!/bin/bash

# Writes appcast.xml for one release: the feed the app reads (SUFeedURL, the
# appcast.xml on the develop branch) to learn of a new version. The disk image
# is signed with the release's EdDSA key, whose public half is SUPublicEDKey
# in the app's Info.plist; Sparkle in installed copies refuses an update whose
# signature does not verify with the key that build pins.
#
# Usage: SPARKLE_KEY_FILE=<private-key-file> \
#            bash .github/scripts/appcast.sh <Clipy-x.y.z.dmg> <vX.Y.Z>
#
# The key is read from SPARKLE_KEY_FILE (a file holding the base64 private key,
# as the SPARKLE_PRIVATE_KEY secret does). Without it the script fails: an
# entry this app cannot verify would hide the update from every installed copy.
#
# APPCAST names the feed to insert the item into (default: appcast.xml in the
# repository root). The release run passes the develop branch's copy, so
# entries added since the tag are kept.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${1:?Usage: appcast.sh <Clipy-x.y.z.dmg> <vX.Y.Z>}"
TAG="${2:?Usage: appcast.sh <Clipy-x.y.z.dmg> <vX.Y.Z>}"
REPO="${GITHUB_REPOSITORY:-Proximity333/Clipy}"
SPARKLE_KEY_FILE="${SPARKLE_KEY_FILE:-}"
APPCAST="${APPCAST:-$ROOT_DIR/appcast.xml}"

[[ -f "$IMAGE" ]] || { printf 'No such image: %s.\n' "$IMAGE" >&2; exit 2; }
[[ -f "$APPCAST" ]] || { printf 'No such appcast: %s.\n' "$APPCAST" >&2; exit 2; }
[[ -n "$SPARKLE_KEY_FILE" && -f "$SPARKLE_KEY_FILE" ]] || {
    printf 'SPARKLE_KEY_FILE is not set or does not name a private key.\n' >&2
    exit 2
}

# The version is the app's, read from inside the image, so the feed can only
# advertise what the disk image carries.
mount="$(mktemp -d)"
cleanup() { hdiutil detach "$mount" -quiet 2>/dev/null || true; rmdir "$mount" 2>/dev/null || true; }
trap cleanup EXIT
hdiutil attach "$IMAGE" -nobrowse -readonly -mountpoint "$mount" >/dev/null
plist="$mount/Clipy.app/Contents/Info.plist"
short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist" 2>/dev/null || echo 26.0)"
hdiutil detach "$mount" -quiet
rmdir "$mount"
trap - EXIT

attributes="$("$ROOT_DIR/Pods/Sparkle/bin/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" "$IMAGE")"
[[ "$attributes" == *edSignature=* ]] || { printf 'sign_update produced no signature.\n' >&2; exit 1; }
signature="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$attributes")"
length="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$attributes")"

name="$(basename "$IMAGE")"
date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
item="$(cat <<XML
    <item>
      <title>Clipy $short</title>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$short</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <pubDate>$date</pubDate>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/$TAG</sparkle:releaseNotesLink>
      <link>https://github.com/$REPO/releases/tag/$TAG</link>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$name"
                 type="application/octet-stream"
                 sparkle:edSignature="$signature"
                 length="$length" />
    </item>
XML
)"

python3 - "$APPCAST" "$item" "$build" <<'PY'
import re
import sys

path, item, version = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as handle:
    document = handle.read()

# A re-run for the same version replaces its item instead of listing it twice.
for match in reversed(list(re.finditer(r"[ \t]*<item>.*?</item>[ \t]*\n?", document, re.S))):
    if f"<sparkle:version>{version}</sparkle:version>" in match.group(0):
        document = document[: match.start()] + document[match.end() :]

# Newest first: at the start of the first item's line, or before the channel
# closes when the feed holds none yet.
index = document.find("<item>")
if index == -1:
    index = document.rfind("</channel>")
    if index == -1:
        sys.exit(f"{path} has no channel.")
else:
    index = document.rfind("\n", 0, index) + 1
document = document[:index] + item + "\n" + document[index:]

with open(path, "w", encoding="utf-8") as handle:
    handle.write(document)
PY

cat "$APPCAST"