#!/bin/bash
# The installed aoe4.sh finds its home from where it is, not from a path written into it.
#
# It used to hold DEST="<absolute path>", filled in by setup.sh. A home moved, copied or
# mounted somewhere else (a disk image at /Volumes/satoru-aoe4, found on 2026-10-06 with a
# real 3.3 GB home) kept using the OLD path for the engine, the prefix, the logs and the
# shader cache, so a moved home silently worked on, or failed against, the one it came from.
#
# `--print-env` resolves every path and exits before anything is launched, so this needs
# no engine, no Steam and no prefix.
set -u
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

check() {
    if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: expected $3, got $2"; fail=1; fi
}

mkhome() {
    mkdir -p "$1"
    cp aoe4.sh "$1/aoe4.sh"
    printf 'pace = 60\n' > "$1/aoe4.conf"
}
resolved() { # the WINEPREFIX line of --print-env
    bash "$1/aoe4.sh" --print-env 2>/dev/null | grep '^WINEPREFIX=' | head -1
}

home1="$work/first home"          # a space in the path on purpose
mkhome "$home1"
real1=$(cd "$home1" && pwd -P)
check "prefix is under the home the script sits in" "$(resolved "$home1")" "WINEPREFIX=$real1/prefix"

home2="$work/second"
mv "$home1" "$home2"
real2=$(cd "$home2" && pwd -P)
check "after the home is moved, the prefix follows it" "$(resolved "$home2")" "WINEPREFIX=$real2/prefix"

# Through a symlink to the home (a mount point reached by another name): the real place wins.
ln -s "$home2" "$work/alias"
check "through a symlink to the home" "$(resolved "$work/alias")" "WINEPREFIX=$real2/prefix"

# No path of the machine that built the pack may remain in the script.
if grep -q '__DEST__' aoe4.sh; then echo "FAIL  aoe4.sh still carries a __DEST__ placeholder"; fail=1; else echo "ok    no __DEST__ placeholder left"; fi

exit "$fail"
