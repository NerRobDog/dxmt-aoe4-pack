#!/bin/bash
# Same inputs, same bytes - so the sha256 in a manifest can be re-derived by
# anyone from the same commit and artifacts, and a rebuild is not a new
# release. Ported from prime-world-pack's test-make-pack.sh, trimmed to the
# checks that hold for this pack's own make-pack.sh (it does not strip
# Engine/include or tests/ from the tarball the way prime-world-pack's does,
# so those two checks were left out rather than asserted against behaviour
# this pack doesn't have).
set -u
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0
say() { if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: expected '$3', got '$2'"; fail=1; fi; }

# Enough for setup.sh --preflight to get past every -e/-x/-f check it makes
# without dying 2/12/127 (the codes make-pack.sh's own preflight gate treats
# as a refusal to build): a dummy wine/x87sidecar, not a working one. The
# x87sidecar stub exits 1 and prints nothing, so --probe never finds
# "supported" and preflight answers 10 - a code make-pack.sh's case statement
# already accepts ("understood, good enough to ship"), same as an unready
# machine would.
art="$work/artifacts"
mkdir -p "$art/Engine/bin" "$art/Engine/lib/wine/x86_64-unix" "$art/Helpers" \
         "$art/dxmt/x86_64-windows" "$art/deps/Frameworks"
printf '#!/bin/sh\nexit 0\n' > "$art/Engine/bin/wine"; chmod +x "$art/Engine/bin/wine"
echo ntdll   > "$art/Engine/lib/wine/x86_64-unix/ntdll.so"
printf '#!/bin/sh\nexit 1\n' > "$art/Helpers/x87sidecar"; chmod +x "$art/Helpers/x87sidecar"
echo dll     > "$art/dxmt/x86_64-windows/d3d12.dll"
echo gnutls  > "$art/deps/Frameworks/libgnutls.30.dylib"
echo inotify > "$art/deps/Frameworks/libinotify.dylib"

build() { bash tools/make-pack.sh "$art" v0.0-test "$1" >"$1.log" 2>&1; }
build "$work/out1" || { echo "FAIL  first build:"; cat "$work/out1.log"; exit 1; }
# Perturb what a second, later build of the same commit would plausibly
# differ in - an artifact's mtime and mode - without changing any content.
# Same bytes despite this is the actual claim; same bytes because nothing
# about the inputs changed would prove nothing.
touch -t 203001010000 "$art/Engine/bin/wine" "$art/dxmt/x86_64-windows/d3d12.dll"
chmod 600 "$art/deps/Frameworks/libgnutls.30.dylib"
build "$work/out2" || { echo "FAIL  second build:"; cat "$work/out2.log"; exit 1; }

a=$(shasum -a 256 "$work"/out1/*.tar.gz | cut -d' ' -f1)
b=$(shasum -a 256 "$work"/out2/*.tar.gz | cut -d' ' -f1)
say "two builds from the same inputs are the same bytes" "$a" "$b"

# Same bytes alone doesn't prove the archive's own member order is canonical -
# a filesystem whose readdir order happens to be stable across two builds on
# THIS machine would pass "same bytes" even without the sort, and would still
# disagree with a different machine's (or a different filesystem's) readdir
# order. Trailing "/" on directory entries (0x2F) sorts after "-" (0x2D), so
# strip it before comparing to a plain LC_ALL=C sort.
order=$(tar -tzf "$work"/out1/*.tar.gz | sed 's#/$##')
say "archive entries in LC_ALL=C sorted order" \
    "$(printf '%s\n' "$order" | shasum -a 256 | cut -d' ' -f1)" \
    "$(printf '%s\n' "$order" | LC_ALL=C sort | shasum -a 256 | cut -d' ' -f1)"

say "every entry owned by root:wheel" \
    "$(tar -tzvf "$work"/out1/*.tar.gz | awk '$3!="root" || $4!="wheel"' | grep -c .)" "0"

# SHA256SUMS' own entry order must not depend on the machine's locale: a
# collation-aware sort orders filenames differently from a byte-order sort,
# and the manifest's sha256 has to be re-derivable by anyone regardless of
# which locale built it.
buildC="$work/out-locale-c"
buildUS="$work/out-locale-us"
env LC_ALL=C          bash tools/make-pack.sh "$art" v0.0-test "$buildC"  >"$buildC.log" 2>&1 \
    || { echo "FAIL  LC_ALL=C build:"; cat "$buildC.log"; exit 1; }
env LC_ALL=en_US.UTF-8 bash tools/make-pack.sh "$art" v0.0-test "$buildUS" >"$buildUS.log" 2>&1 \
    || { echo "FAIL  LC_ALL=en_US.UTF-8 build:"; cat "$buildUS.log"; exit 1; }

sumsC=$(tar -xzf "$buildC"/*.tar.gz -O '*/SHA256SUMS')
sumsUS=$(tar -xzf "$buildUS"/*.tar.gz -O '*/SHA256SUMS')
say "SHA256SUMS is byte-identical under LC_ALL=C and LC_ALL=en_US.UTF-8" \
    "$(printf '%s' "$sumsUS" | shasum -a 256 | cut -d' ' -f1)" \
    "$(printf '%s' "$sumsC"  | shasum -a 256 | cut -d' ' -f1)"
say "SHA256SUMS' file list is in plain C byte order" \
    "$(printf '%s\n' "$sumsC" | awk '{print $2}')" \
    "$(printf '%s\n' "$sumsC" | awk '{print $2}' | LC_ALL=C sort)"
say "the two builds are the same bytes end to end" \
    "$(shasum -a 256 "$buildUS"/*.tar.gz | cut -d' ' -f1)" \
    "$(shasum -a 256 "$buildC"/*.tar.gz | cut -d' ' -f1)"

echo
[ "$fail" = 0 ] && echo "make-pack is reproducible." || echo "MAKE-PACK IS NOT REPRODUCIBLE"
exit "$fail"
