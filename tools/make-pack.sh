#!/bin/bash
# Build the release tarball for this pack — and refuse to build one that does not
# implement the contract its own game.toml declares.
#
#   tools/make-pack.sh <artifacts-dir> <version> [out-dir]
#
# <artifacts-dir> holds the binary payload that is not in git: Engine/, Helpers/,
# dxmt/ and deps/. Everything else comes from the checked-out tree, so what ships
# is what is committed.
#
# Two things here are not decoration.
#
# COPYFILE_DISABLE=1: without it macOS tar writes an AppleDouble `._name` beside
# every entry whose file carries extended attributes. Those ship inside the
# tarball, and a `._pack` next to `pack/` makes the archive look multi-rooted to
# whatever unpacks it — satoru then runs the pack's commands one directory too
# high and reports `bash: setup.sh: No such file or directory`.
#
# The preflight gate: v0.1 was cut before setup.sh learned --preflight, and the
# manifest that declared it pointed at that release anyway. The result was a
# 139 MB download that ended in "unknown flag --preflight". A manifest describes
# a pack; this refuses to build a pack that cannot answer its own manifest.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="${1:-}"
VERSION="${2:-}"
OUT="${3:-$HERE/dist}"

die() { printf '%s\n' "$*" >&2; exit 1; }

[ -n "$ARTIFACTS" ] && [ -n "$VERSION" ] || die \
  "usage: tools/make-pack.sh <artifacts-dir> <version> [out-dir]
       artifacts-dir holds Engine/ Helpers/ dxmt/ deps/"
[ -d "$ARTIFACTS" ] || die "no such artifacts directory: $ARTIFACTS"
[ -f "$HERE/game.toml" ] || die "no game.toml in $HERE — is this a pack?"
for part in Engine Helpers dxmt deps; do
  [ -e "$ARTIFACTS/$part" ] || die "artifacts are incomplete: $ARTIFACTS/$part is missing"
done

# The repository's name, not the checkout's: as a satoru submodule this tree sits
# at games/aoe4, and a tarball rooted at aoe4/ with a URL to /aoe4/releases would
# be wrong in both places.
ORIGIN="$(cd "$HERE" && git config --get remote.origin.url 2>/dev/null || true)"
NAME="$(basename -s .git "${ORIGIN:-$HERE}")"
STAGE="$(mktemp -d)/$NAME"
trap 'rm -rf "$(dirname "$STAGE")"' EXIT
mkdir -p "$STAGE"

echo "Staging tracked files..."
( cd "$HERE" && git ls-files -z ) | ( cd "$HERE" && xargs -0 -I{} \
  bash -c 'mkdir -p "$0/$(dirname "{}")" && cp -p "{}" "$0/{}"' "$STAGE" )

echo "Staging the binary payload..."
for part in Engine Helpers dxmt deps; do
  rm -rf "${STAGE:?}/$part"
  cp -R "$ARTIFACTS/$part" "$STAGE/$part"
done

# The gate. preflight is the one command the contract promises writes nothing, so
# it is the one a build script may run. Exit 2 and 127 mean the pack did not
# understand what its own manifest declares; every other code is an answer.
PREFLIGHT="$(sed -n 's/^preflight[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
             "$HERE/game.toml" | head -1)"
if [ -n "$PREFLIGHT" ]; then
  echo "Asking the staged pack its own preflight: $PREFLIGHT"
  set +e
  ( cd "$STAGE" && SATORU_GAME_HOME="$(mktemp -d)" SATORU_CONTRACT=1 \
      bash -c "$PREFLIGHT" >/dev/null 2>&1 )
  code=$?
  set -e
  case "$code" in
    2|127) die "the staged pack answered $code to \`$PREFLIGHT\` — it does not implement
the manifest it ships with. Build refused: this is how a release ends up older
than the manifest pointing at it." ;;
    *) echo "  answered $code — understood, good enough to ship" ;;
  esac
fi

echo "Hashing..."
( cd "$STAGE" && find . -type f ! -name SHA256SUMS -print0 \
    | sort -z | xargs -0 shasum -a 256 > SHA256SUMS )

mkdir -p "$OUT"
TARBALL="$OUT/$NAME-$VERSION.tar.gz"
rm -f "$TARBALL"
echo "Building $TARBALL..."
COPYFILE_DISABLE=1 tar -czf "$TARBALL" -C "$(dirname "$STAGE")" "$NAME"

if tar -tzf "$TARBALL" | grep -q '^\._\|/\._'; then
  die "the tarball contains AppleDouble entries — COPYFILE_DISABLE did not take"
fi

SHA="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
SIZE="$(wc -c < "$TARBALL" | tr -d ' ')"

echo
echo "built $TARBALL"
echo "  sha256: $SHA"
echo "  size:   $SIZE bytes"
echo
echo "Paste into game.toml, then publish the release before anyone reads it:"
echo
echo "[source]"
echo "kind    = \"release\""
echo "url     = \"https://github.com/NerRobDog/$NAME/releases/download/$VERSION/$NAME-$VERSION.tar.gz\""
echo "sha256  = \"$SHA\""
echo "size    = $SIZE"
echo "version = \"$VERSION\""
echo "check   = \"github-release\""
