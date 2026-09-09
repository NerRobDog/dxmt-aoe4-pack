#!/bin/bash
# dxmt-aoe4-pack bootstrap: download the release archive (the binaries are not in git),
# verify it, unpack it next to your Downloads and run setup.sh. Re-run to update.
#   bash bootstrap.sh [--fresh|--clone]     (flags are passed to setup.sh)
set -euo pipefail
VERSION="v0.1"
URL="https://github.com/NerRobDog/dxmt-aoe4-pack/releases/download/$VERSION/dxmt-aoe4-pack-$VERSION.tar.gz"
SHA256="0540919b44aaa83ab33ef7e16b6ed2da665f3b0a588bf5e1a82b1cdb5c715b4d"
DL="${AOE4_PACK_DOWNLOADS:-$HOME/Downloads}"
mkdir -p "$DL"
ARCHIVE="$DL/dxmt-aoe4-pack-$VERSION.tar.gz"
if [ ! -f "$ARCHIVE" ] || [ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" != "$SHA256" ]; then
  echo "Downloading $URL (133 MB) ..."
  curl -fL --progress-bar -o "$ARCHIVE.part" "$URL"
  mv "$ARCHIVE.part" "$ARCHIVE"
fi
GOT=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
[ "$GOT" = "$SHA256" ] || { echo "ERROR: sha256 of $ARCHIVE is $GOT, expected $SHA256. Delete it and re-run." >&2; exit 1; }
echo "Archive verified. Unpacking to $DL/dxmt-aoe4-pack ..."
rm -rf "$DL/dxmt-aoe4-pack"
tar -xzf "$ARCHIVE" -C "$DL"
cd "$DL/dxmt-aoe4-pack" && shasum -c SHA256SUMS --quiet && echo "Pack files verified."
exec bash setup.sh "$@"
