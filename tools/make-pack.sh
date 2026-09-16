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

# What builds a release is not part of it. bootstrap.sh downloads the tarball, so
# inside the tarball it has nothing to fetch and only rots; tools/ builds the
# tarball, which nobody does from inside one. Both belong to a clone of the
# repository, and keeping them out is also what lets the version check below be
# strict: the line in make-pack.sh that prints a [source] block for pasting is a
# generator of the one copy, not a second copy, and it never reaches the pack.
rm -f "${STAGE:?}/bootstrap.sh"
rm -rf "${STAGE:?}/tools"

echo "Staging the binary payload..."
for part in Engine Helpers dxmt deps; do
  rm -rf "${STAGE:?}/$part"
  cp -R "$ARTIFACTS/$part" "$STAGE/$part"
done

# Wine's build-time import libraries: 503 files, 19 MB, and nothing at runtime
# opens one — the game links against the .dll and .so beside them. They are only
# needed by a build, and the pack does not build anything; it copies. If a
# winegcc path ever appears here, this line is what has to go.
find "${STAGE:?}/Engine" -name '*.a' -delete 2>/dev/null || true

# The engine's revision, carried into the pack so the attribution can be checked
# against it and so anyone holding the tarball can ask what built it. The binary
# will not say: its only version string is `wine-11.0`, in the 27 KB bin/wine
# loader and in ntdll.so alike.
#
# It comes from the engine build if that left one behind, or from the environment
# when a human knows what they built. Neither is a hard requirement: the v0.1
# engine predates the idea, and refusing to package it would help nobody.
ENGINE_ID=""
[ -s "$ARTIFACTS/Engine/.build-id" ] && ENGINE_ID="$(tr -d '[:space:]' < "$ARTIFACTS/Engine/.build-id")"
[ -z "$ENGINE_ID" ] && ENGINE_ID="${AOE4_ENGINE_COMMIT:-}"
if [ -n "$ENGINE_ID" ]; then
  printf '%s\n' "$ENGINE_ID" > "${STAGE:?}/Engine/.build-id"
  echo "Engine built from $ENGINE_ID"
else
  echo "WARNING: no engine revision recorded. The pack will ship without one, so
         THIRD_PARTY.md cannot be checked against what was actually built. Pass
         AOE4_ENGINE_COMMIT=<sha> to record it." >&2
fi

# One version, in one file. Checked before anything is hashed, so a pack that
# names a release in two places never reaches a tarball.
bash "$HERE/tools/check-version.sh" "$VERSION" "$STAGE" || die \
  "Build refused by tools/check-version.sh (above)."

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
    12) die "the staged pack answered 12 to \`$PREFLIGHT\` — pack incomplete
(missing Engine/Helpers/deps). Build refused." ;;
    *) echo "  answered $code — understood, good enough to ship" ;;
  esac
fi

# The profile rename is the one thing in this pack that can destroy what the
# player already has: run against an engine that still calls the profile
# crossover, it moves the directory out from under that engine, which then finds
# nothing and builds an empty profile beside it. The guard is that the name comes
# from Engine/.profile-user and an absent file means no rename - and that guard
# is worth proving on the staged copy rather than trusting, because the version
# without it existed in prime-world-pack's repository for two commits and looked
# correct (found and fixed there first: 276a5e8, proven here: 5f4bd04).
if [ -f "$STAGE/migrate-prefix-user.sh" ]; then
  echo "Proving the staged migration does nothing without a name from the engine..."
  probe="$(mktemp -d)"
  mkdir -p "$probe/drive_c/users/crossover/Documents"
  printf 'WINE REGISTRY Version 2\n"USERNAME"="crossover"\n' > "$probe/system.reg"
  printf 'WINE REGISTRY Version 2\n"USERNAME"="crossover"\n' > "$probe/user.reg"
  set +e
  out="$(bash "$STAGE/migrate-prefix-user.sh" "$probe" 2>&1)"; code=$?
  set -e
  [ "$code" = 0 ] || die "the staged migrate-prefix-user.sh answered $code with no profile
name; it must do nothing and say nothing. Build refused."
  [ -z "$out" ] || die "the staged migrate-prefix-user.sh spoke with no profile name:
$out
It must be silent for engines that do not declare one. Build refused."
  [ -d "$probe/drive_c/users/crossover" ] || die "the staged migrate-prefix-user.sh renamed
the profile with no name declared by the engine. That is the failure this guard
exists for: shipped with an older engine it would strand the player's settings.
Build refused."
  rm -rf "$probe"
fi

echo "Hashing..."
# LC_ALL=C: an unset or inherited locale makes sort's collation - and so the
# entry order of SHA256SUMS, and so its own bytes - depend on the machine that
# built the release. The pack_id a home records is a hash of this file; two
# builds from the same commit must produce the same one everywhere.
( cd "$STAGE" && find . -type f ! -name SHA256SUMS -print0 \
    | LC_ALL=C sort -z | xargs -0 shasum -a 256 > SHA256SUMS )

mkdir -p "$OUT"
TARBALL="$OUT/$NAME-$VERSION.tar.gz"
rm -f "$TARBALL"
echo "Building $TARBALL..."
# Reproducible: the same inputs give the same bytes. Three things made it vary -
# file times, the order bsdtar walks a directory, and gzip's own timestamp - and
# two more would on another machine: owners and modes.
EPOCH="${SOURCE_DATE_EPOCH:-$(cd "$HERE" && git log -1 --format=%ct)}"
STAMP="$(date -u -r "$EPOCH" +%Y%m%d%H%M.%S)"
chmod -R u+rwX,go+rX,go-w "$STAGE"
find "$STAGE" -exec env TZ=UTC0 touch -h -t "$STAMP" {} +
LIST="$(dirname "$STAGE")/.list"
( cd "$(dirname "$STAGE")" && find "$NAME" | LC_ALL=C sort ) > "$LIST"
COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs --no-acls --no-fflags \
    --uid 0 --gid 0 --uname root --gname wheel -n \
    -cf - -C "$(dirname "$STAGE")" -T "$LIST" | gzip -n -9 > "$TARBALL"

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
