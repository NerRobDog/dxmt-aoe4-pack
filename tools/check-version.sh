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

if [ "$bad" = 1 ]; then
  echo "
Build refused: the release version belongs in game.toml and nowhere else.
Everything that needs it reads it from there." >&2
  exit 1
fi
