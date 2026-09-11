#!/bin/bash
# dxmt-aoe4-pack bootstrap: download the release archive (the binaries are not in git),
# verify it, unpack it next to your Downloads and run setup.sh. Re-run to update.
#   bash bootstrap.sh [--fresh|--clone]     (flags are passed to setup.sh)
#
# Which release to fetch is read from game.toml, not written down here. It used to
# be written down here, and then v0.2 would have shipped a bootstrap that fetches
# v0.1: two copies of one fact, and nothing comparing them. The manifest is the
# copy that satoru already reads, so it is the one that gets to be right.
#
# This script belongs to a clone of the repository, where the binaries are absent.
# It is deliberately not shipped inside the tarball: a downloader inside the thing
# it downloads has nothing to do, and goes stale the moment the next release lands.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/game.toml"
[ -f "$MANIFEST" ] || {
  echo "ERROR: no game.toml next to this script. Run it from a clone of the repository." >&2
  exit 1
}

# The manifest subset keeps these three as quoted single-line strings, so one sed
# is enough and no TOML reader has to exist on a Mac that ships Python 3.9.
field() {
  sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*\$/\1/p" "$MANIFEST" | head -1
}
VERSION="$(field version)"
URL="$(field url)"
SHA256="$(field sha256)"

for pair in "version:$VERSION" "url:$URL" "sha256:$SHA256"; do
  [ -n "${pair#*:}" ] || {
    echo "ERROR: game.toml has no [source] ${pair%%:*}. This pack has no published release yet." >&2
    exit 1
  }
done

DL="${AOE4_PACK_DOWNLOADS:-$HOME/Downloads}"
mkdir -p "$DL"
ARCHIVE="$DL/$(basename "$URL")"
# The tarball is <pack>-<version>.tar.gz and unpacks to <pack>/.
ROOT="$(basename "$ARCHIVE" .tar.gz)"; ROOT="${ROOT%-$VERSION}"

if [ ! -f "$ARCHIVE" ] || [ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" != "$SHA256" ]; then
  echo "Downloading $VERSION from $URL ..."
  curl -fL --progress-bar -o "$ARCHIVE.part" "$URL"
  mv "$ARCHIVE.part" "$ARCHIVE"
fi
GOT=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
[ "$GOT" = "$SHA256" ] || { echo "ERROR: sha256 of $ARCHIVE is $GOT, expected $SHA256. Delete it and re-run." >&2; exit 1; }
echo "Archive verified. Unpacking to $DL/$ROOT ..."
rm -rf "${DL:?}/$ROOT"
tar -xzf "$ARCHIVE" -C "$DL"
cd "$DL/$ROOT" && shasum -c SHA256SUMS --quiet && echo "Pack files verified."
exec bash setup.sh "$@"
