#!/bin/bash
# setup.sh's preflight used to refuse on ANY wineserver on the Mac
# (`pgrep -q wineserver`). Several packs' homes coexist on the same machine
# (see ~/ow2/CLAUDE.md's directory-ownership table) and each has its own
# Engine/ copy and its own prefix, so a wineserver belonging to a different
# home - a different game entirely, or another AoE4 pack's home - must not
# block this home's install or preflight. Only a wineserver actually serving
# THIS home's prefix, or (in clone mode) the bottle this run is about to
# copy, is a real conflict.
#
# This exercises real setup.sh, with a fake pack directory standing in for
# Engine/Helpers/deps (so the pack-completeness gates pass without a real
# ~420 MB engine) and a fake pgrep/ps on PATH standing in for the process
# table, exactly as tests/test-migrate-prefix-user.sh already does for the
# same reason.
set -u
cd "$(dirname "$0")/.."
SETUP_SH="$(pwd)/setup.sh"

fail=0
check() {
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: expected $3, got $2"
        fail=1
    fi
}

# A minimal pack directory: just enough for setup.sh's own pack-completeness
# checks (host checks + "pack is incomplete" gates) to pass, so preflight
# actually reaches the wineserver guard instead of dying earlier for reasons
# unrelated to this test. Engine/deps/Helpers are never read for real content
# during --preflight - only existence/executability is checked - so empty
# stand-ins are enough. x87sidecar's --probe output is real content: the
# guard runs after it, so it has to report "supported" or preflight would die
# 10 for the wrong reason before ever reaching the wineserver check.
make_fake_pack() {
    local pack="$1"
    mkdir -p "$pack/Engine/bin" "$pack/Engine/lib/wine/x86_64-unix" "$pack/Helpers" "$pack/deps/Frameworks"
    : > "$pack/Engine/bin/wine"; chmod +x "$pack/Engine/bin/wine"
    : > "$pack/Engine/lib/wine/x86_64-unix/ntdll.so"
    : > "$pack/deps/Frameworks/libgnutls.30.dylib"
    : > "$pack/deps/Frameworks/libinotify.dylib"
    cat > "$pack/Helpers/x87sidecar" <<'SH'
#!/bin/bash
echo "probe: fake sidecar"
echo "supported"
SH
    chmod +x "$pack/Helpers/x87sidecar"
    ln -s "$SETUP_SH" "$pack/setup.sh"
}

# A fake pgrep/ps pair ahead of the real ones on PATH: one wineserver pid,
# whose `ps eww` command line carries WINEPREFIX=<target>. Mirrors
# install_wineserver_shim in tests/test-migrate-prefix-user.sh, and what
# setup.sh's guard actually reads.
install_wineserver_shim() {
    local bin="$1" target="$2"
    mkdir -p "$bin"
    cat > "$bin/pgrep" <<'SH'
#!/bin/bash
echo 4242
SH
    cat > "$bin/ps" <<SH
#!/bin/bash
echo "wineserver -p WINEPREFIX=$target -foreground"
SH
    chmod +x "$bin/pgrep" "$bin/ps"
}

# No wineserver at all: pgrep finds nothing.
install_no_wineserver_shim() {
    local bin="$1"
    mkdir -p "$bin"
    cat > "$bin/pgrep" <<'SH'
#!/bin/bash
exit 1
SH
    cat > "$bin/ps" <<'SH'
#!/bin/bash
exit 1
SH
    chmod +x "$bin/pgrep" "$bin/ps"
}

run_preflight() {
    # HOME is overridden so the "no explicit AOE4_STEAMAPPS" fallback scan of
    # $HOME/Games/*/steamapps can't pick up a real Steam library on this
    # machine and fail the test for an unrelated reason (an exe sha mismatch).
    local work="$1"; shift
    ( cd "$work" && env -i PATH="$work/bin:$PATH" HOME="$work/fakehome" "$@" bash "$work/pack/setup.sh" --preflight ) >"$work/out.log" 2>&1
    echo $?
}

# ---------------------------------------------------------- foreign wineserver

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
make_fake_pack "$work/pack"
mkdir -p "$work/fakehome"
install_wineserver_shim "$work/bin" "/some/other/pack/home/prefix"
code=$(run_preflight "$work" AOE4_PACK_HOME="$work/home")
check "a wineserver on an unrelated prefix is not refused" "$code" 0
rm -rf "$work"

# ------------------------------------------------------ this home's wineserver

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
make_fake_pack "$work/pack"
mkdir -p "$work/fakehome" "$work/home/prefix"
install_wineserver_shim "$work/bin" "$work/home/prefix"
code=$(run_preflight "$work" AOE4_PACK_HOME="$work/home")
check "a wineserver already serving this home's own prefix is refused" "$code" 10
check "  nothing was written to the home" \
    "$(find "$work/home" -mindepth 1 ! -path "$work/home/prefix" | wc -l | tr -d ' ')" 0
rm -rf "$work"

# ------------------------------- this home's wineserver, spelled differently

# Wine accepts WINEPREFIX with a trailing slash or through a symlink, and the
# server it starts serves the same prefix either way; the guard has to compare
# the directory, not the spelling.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
make_fake_pack "$work/pack"
mkdir -p "$work/fakehome" "$work/home/prefix"
install_wineserver_shim "$work/bin" "$work/home/prefix/"
code=$(run_preflight "$work" AOE4_PACK_HOME="$work/home")
check "this home's prefix with a trailing slash is refused" "$code" 10
rm -rf "$work"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
make_fake_pack "$work/pack"
mkdir -p "$work/fakehome" "$work/home/prefix"
ln -s "$work/home" "$work/home-link"
install_wineserver_shim "$work/bin" "$work/home-link/prefix"
code=$(run_preflight "$work" AOE4_PACK_HOME="$work/home")
check "this home's prefix reached through a symlink is refused" "$code" 10
rm -rf "$work"

# --------------------------------------------- clone source bottle's wineserver

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
make_fake_pack "$work/pack"
mkdir -p "$work/fakehome" "$work/bottle/drive_c"
install_wineserver_shim "$work/bin" "$work/bottle"
code=$(run_preflight "$work" AOE4_PACK_HOME="$work/home" AOE4_BOTTLE="$work/bottle")
check "a wineserver serving the clone source bottle is refused" "$code" 10
check "  the destination home was not created" "$([ -e "$work/home" ] && echo yes || echo no)" no
rm -rf "$work"

# ------------------------------------------------------------- no wineserver

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
make_fake_pack "$work/pack"
mkdir -p "$work/fakehome"
install_no_wineserver_shim "$work/bin"
code=$(run_preflight "$work" AOE4_PACK_HOME="$work/home")
check "no wineserver running at all is not refused" "$code" 0
rm -rf "$work"

exit "$fail"
