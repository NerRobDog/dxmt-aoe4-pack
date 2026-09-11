#!/bin/bash
# Refuse a pack in which the release version is written down more than once.
#
#   tools/check-version.sh <version> <dir>
#
# <dir> is a staged pack: the tree that is about to become the tarball.
#
# The version used to live in four places — game.toml, bootstrap.sh, README.md
# and INSTALL.md — and nothing compared them. Cutting v0.2 would have shipped a
# bootstrap that downloads v0.1 and docs naming a file nobody published. Rather
# than compare four copies, this enforces that there is only ever one: the
# manifest. Everything else reads it or says nothing.
#
# Two things are refused outside game.toml:
#
#   <pack>-v<X>   a release tarball's name — the only reason to write one down
#                 is to point at a release, and pointing is the manifest's job;
#   the release download path, for the same reason.
#
# game.toml itself is exempt, and not as a special case: the release is cut
# first and the manifest follows it, so while v0.2 is being built the manifest
# still legitimately names v0.1. A check that refused that would forbid the one
# ordering the contract insists on.
#
# A version that belongs to something else is not a release of this pack:
# setup.sh greps DXMT's `v0.80-` build stamp and THIRD_PARTY.md names Wine 11.0.
# Matching is anchored to the pack's own name, so neither is mistaken for one.
set -euo pipefail

VERSION="${1:-}"
DIR="${2:-}"

[ -n "$VERSION" ] && [ -n "$DIR" ] || {
  echo "usage: tools/check-version.sh <version> <staged-dir>" >&2
  exit 2
}
[ -d "$DIR" ] || { echo "no such directory: $DIR" >&2; exit 2; }

NAME="$(basename "$(cd "$(dirname "$0")/.." && pwd)")"
# As a satoru submodule this tree is checked out at games/aoe4, so the directory
# name is not the pack's name. The repository knows its own.
ORIGIN="$(cd "$(dirname "$0")/.." && git config --get remote.origin.url 2>/dev/null || true)"
[ -n "$ORIGIN" ] && NAME="$(basename -s .git "$ORIGIN")"

bad=0
report() { echo "$1" >&2; bad=1; }

while IFS= read -r file; do
  rel="${file#$DIR/}"
  [ "$rel" = "game.toml" ] && continue
  case "$rel" in .git/*) continue ;; esac

  # A tarball of this pack, at any version other than the one being built. The
  # version being built is allowed: that is a file correctly naming its own release.
  hits="$(grep -n -- "$NAME-v" "$file" 2>/dev/null | grep -v -- "$NAME-$VERSION" || true)"
  [ -n "$hits" ] && report "$rel names a release other than $VERSION:
$hits"

  urls="$(grep -n -- "releases/download/" "$file" 2>/dev/null || true)"
  [ -n "$urls" ] && report "$rel carries a release URL; only game.toml may point at a release:
$urls"
done < <(find "$DIR" -type f ! -name SHA256SUMS)

# The engine's revision, where the build recorded one. LGPL asks that the source
# offer point at what was actually shipped, and the binary itself cannot say: the
# only version string in it is `wine-11.0`, in bin/wine (a 27 KB loader) and in
# ntdll.so alike. The upper tree is pinned by the sha256 of its source tarball,
# which is stronger than a commit; it is our delta on top that had nothing
# holding it, and Engine/.build-id is what holds it now.
#
# A pack without one is not refused. The engine of v0.1 carries none, and a check
# that blocked on that would make every older build unshippable; make-pack.sh
# says so out loud instead.
BUILD_ID_FILE="$DIR/Engine/.build-id"
if [ -s "$BUILD_ID_FILE" ]; then
  build_id="$(tr -d '[:space:]' < "$BUILD_ID_FILE")"
  attribution="$DIR/THIRD_PARTY.md"
  if [ ! -f "$attribution" ]; then
    report "Engine/.build-id names $build_id, but there is no THIRD_PARTY.md to credit it in"
  else
    named=0
    # Word-bounded, so the 64-character sha256 sums this file is full of cannot
    # have a 40-character prefix mistaken for a commit.
    while IFS= read -r token; do
      case "$build_id" in "$token"*) named=1; break ;; esac
    done < <(grep -oE '\b[0-9a-f]{7,40}\b' "$attribution" | sort -u)
    [ "$named" = 1 ] || report "THIRD_PARTY.md does not name the engine revision that was built.
Engine/.build-id says $build_id; credit that commit beside the build's repository."
  fi
fi

if [ "$bad" = 1 ]; then
  echo "
Build refused. Each fact above belongs in exactly one place: the release version
in game.toml, the engine revision in Engine/.build-id and the attribution that
credits it. Everything else reads them." >&2
  exit 1
fi
