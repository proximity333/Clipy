#!/bin/bash

# Checks that a release's appcast is signed with the key the app can verify:
# the enclosure's EdDSA signature over the disk image, checked against
# SUPublicEDKey in the Info.plist inside that same image.
#
# Usage: bash .github/scripts/verify-appcast.sh <Clipy-x.y.z.dmg> <appcast.xml>
#
# Sparkle refuses an update whose signature its own build does not verify, so
# a release signed with a key the app does not pin publishes an update nobody
# can install. That is invisible from the build alone: the key pair lives in
# the SPARKLE_PRIVATE_KEY secret, the public half in Info.plist, and nothing
# ties them together until an installed copy tries to update. This ties them
# together before the feed is pushed.

set -euo pipefail

IMAGE="${1:?Usage: verify-appcast.sh <Clipy-x.y.z.dmg> <appcast.xml>}"
APPCAST="${2:?Usage: verify-appcast.sh <Clipy-x.y.z.dmg> <appcast.xml>}"
[[ -f "$IMAGE" && -f "$APPCAST" ]] || { printf 'No such file: %s or %s.\n' "$IMAGE" "$APPCAST" >&2; exit 2; }
xmllint --noout "$APPCAST"

signature="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$APPCAST" | head -1)"
length="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' "$APPCAST" | head -1)"
if [[ -z "$signature" ]]; then
    printf 'The appcast lists no EdDSA signature: Sparkle in installed copies refuses such an update.\n' >&2
    exit 1
fi

actual="$(wc -c < "$IMAGE" | tr -d ' ')"
if [[ -n "$length" && "$actual" != "$length" ]]; then
    printf 'The image is %s bytes, the appcast promises %s.\n' "$actual" "$length" >&2
    exit 1
fi

mount="$(mktemp -d)"
cleanup() { hdiutil detach "$mount" -quiet 2>/dev/null || true; rmdir "$mount" 2>/dev/null || true; }
trap cleanup EXIT
hdiutil attach "$IMAGE" -nobrowse -readonly -mountpoint "$mount" >/dev/null
public="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$mount/Clipy.app/Contents/Info.plist")"

program="$(mktemp -t verify-appcast).swift"
cat > "$program" <<'SWIFT'
import Foundation
import CryptoKit
// Args: the image, the base64 signature, the base64 public key the app pins.
let a = CommandLine.arguments
let image = try! Data(contentsOf: URL(fileURLWithPath: a[1]))
guard let signature = Data(base64Encoded: a[2]), let rawKey = Data(base64Encoded: a[3]) else {
    FileHandle.standardError.write(Data("The signature or the key is not base64.\n".utf8))
    exit(2)
}
guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey) else {
    FileHandle.standardError.write(Data("SUPublicEDKey is not an Ed25519 key.\n".utf8))
    exit(2)
}
if key.isValidSignature(signature, for: image) { exit(0) }
FileHandle.standardError.write(Data("The appcast's signature does not verify with the key this build pins.\n".utf8))
exit(1)
SWIFT
if ! swift "$program" "$IMAGE" "$signature" "$public"; then
    printf 'The release feed is signed with a key the app does not know.\n' >&2
    printf 'Set SPARKLE_PRIVATE_KEY to the private half of SUPublicEDKey (%s).\n' "$public" >&2
    exit 1
fi
rm -f "$program"

printf 'The appcast verifies: signed with the key this build pins (%s).\n' "$public"