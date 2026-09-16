#!/bin/bash
# The rename of the profile directory inside an existing prefix.
#
# Our engine used to answer GetUserName with "crossover", the name CrossOver's
# own hack put there; it now answers "satoru" (wine-aoe4 own-identity). A
# prefix made by the old engine - or a bottle cloned by setup.sh's AOE4_BOTTLE
# path - holds C:\users\crossover and a registry full of paths into it. Opened
# with the new engine and left alone, that prefix grows a second, empty
# profile and the player's settings, saves and screenshots stay in the first
# one - silently, and only visible as "the game forgot everything".
#
# So the migration is not optional and it has to be exactly right. What is
# defended here: the directory moves, every path value follows it, the word
# CrossOver where it is a product name and not a path is left alone, running it
# twice changes nothing, a launch while Steam is already up in the same prefix
# is not refused just because a wineserver is running, and it refuses rather
# than guesses when the prefix is in a state it did not expect.
#
# Nothing here needs the engine, Steam, a real prefix or the network. Ported
# from prime-world-pack's migrate-prefix-user.sh (same script, unchanged logic)
# with fixtures rebuilt around this game's own profile path.
set -u
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

check() {
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: expected $3, got $2"
        fail=1
    fi
}

# A prefix the old engine (or a cloned CrossOver bottle) would leave behind:
# the profile directory, the shell folders that point into it, the profile in
# ProfileList, the USERNAME value, and one CrossOver mention that is a product
# name rather than a path.
make_old_prefix() {
    local p="$1"
    mkdir -p "$p/drive_c/users/crossover/Documents/My Games/Age of Empires IV"
    mkdir -p "$p/drive_c/users/Public" "$p/dosdevices"
    echo "the player's settings" > "$p/drive_c/users/crossover/Documents/My Games/Age of Empires IV/configuration_system.lua"
    cat > "$p/user.reg" <<'REG'
WINE REGISTRY Version 2

[Environment] 1600000000
"TEMP"="C:\\users\\crossover\\AppData\\Local\\Temp"
"USERNAME"="crossover"

[Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders] 1600000000
"Desktop"="C:\\users\\crossover\\Desktop"
"Personal"="C:\\users\\crossover\\Documents"

[Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders] 1600000000
"Desktop"=str(2):"%USERPROFILE%\\Desktop"
REG
    cat > "$p/system.reg" <<'REG'
WINE REGISTRY Version 2

[Software\\Microsoft\\Windows NT\\CurrentVersion\\ProfileList\\S-1-5-21-0-0-0-1000] 1600000000
"ProfileImagePath"="C:\\users\\crossover"

[Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\CrossOver Steam] 1600000000
"DisplayName"="CrossOver Steam bottle"
REG
    cat > "$p/userdef.reg" <<'REG'
WINE REGISTRY Version 2

[Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders] 1600000000
"Personal"="C:\\users\\crossover\\Documents"
REG
}

# A fake wineserver holding a given prefix, ahead of the real pgrep/ps on PATH
# for the one invocation that sources it. Mirrors what migrate-prefix-user.sh
# actually reads: `pgrep -f wineserver` for a pid, then `ps eww -o command= -p
# <pid>` for a WINEPREFIX=... token in its command line.
install_wineserver_shim() {
    local bin="$work/bin" target="$1"
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

# ---------------------------------------------------------------- the rename

prefix="$work/old"
make_old_prefix "$prefix"
out=$(bash migrate-prefix-user.sh "$prefix" satoru 2>&1); code=$?

check "a prefix from the old engine migrates" "$code" 0
check "  the profile directory is renamed" \
    "$([ -d "$prefix/drive_c/users/satoru" ] && echo yes || echo no)" yes
check "  the old profile directory is gone" \
    "$([ -e "$prefix/drive_c/users/crossover" ] && echo still-there || echo gone)" gone
check "  what was inside it came along" \
    "$(cat "$prefix/drive_c/users/satoru/Documents/My Games/Age of Empires IV/configuration_system.lua" 2>/dev/null)" \
    "the player's settings"
check "  Public is untouched" \
    "$([ -d "$prefix/drive_c/users/Public" ] && echo yes || echo no)" yes
check "  it says what it did" \
    "$(echo "$out" | grep -c 'crossover')" 1

check "  no path still points at the old profile" \
    "$(grep -ci 'users\\\\crossover' "$prefix"/*.reg | awk -F: '{s+=$2} END {print s+0}')" 0
check "  the shell folders point at the new one" \
    "$(grep -c 'C:\\\\users\\\\satoru\\\\Documents' "$prefix/user.reg")" 1
check "  ProfileImagePath follows" \
    "$(grep -c '"ProfileImagePath"="C:\\\\users\\\\satoru"' "$prefix/system.reg")" 1
check "  userdef.reg follows too" \
    "$(grep -c 'C:\\\\users\\\\satoru\\\\Documents' "$prefix/userdef.reg")" 1
check "  USERNAME follows" \
    "$(grep -c '"USERNAME"="satoru"' "$prefix/user.reg")" 1
check "  the product name CrossOver is left alone" \
    "$(grep -c '"DisplayName"="CrossOver Steam bottle"' "$prefix/system.reg")" 1
check "  %USERPROFILE% entries are left as they are" \
    "$(grep -c 'str(2):"%USERPROFILE%' "$prefix/user.reg")" 1

# ------------------------------------------------------------- running twice

out=$(bash migrate-prefix-user.sh "$prefix" satoru 2>&1); code=$?
check "a second run has nothing to do" "$code" 0
check "  and says nothing" "$out" ""
check "  and the profile is still there" \
    "$([ -d "$prefix/drive_c/users/satoru" ] && echo yes || echo no)" yes

# ------------------------------------------------------------------ dry run

prefix="$work/dry"
make_old_prefix "$prefix"
out=$(bash migrate-prefix-user.sh --dry-run "$prefix" satoru 2>&1); code=$?
check "a dry run reports" "$code" 0
check "  and renames nothing" \
    "$([ -d "$prefix/drive_c/users/crossover" ] && echo yes || echo no)" yes
check "  and rewrites nothing" \
    "$(grep -c '"USERNAME"="crossover"' "$prefix/user.reg")" 1

# -------------------------------------------------- a prefix that is not one

check "a prefix that does not exist is not an error" \
    "$(bash migrate-prefix-user.sh "$work/absent" satoru >/dev/null 2>&1; echo $?)" 0
mkdir -p "$work/empty"
check "a directory that is not a prefix is not an error" \
    "$(bash migrate-prefix-user.sh "$work/empty" satoru >/dev/null 2>&1; echo $?)" 0

# ------------------------------------------------------ a prefix it refuses

# Both profiles present: either could hold the player's things, and picking one
# would throw the other away.
prefix="$work/both"
make_old_prefix "$prefix"
mkdir -p "$prefix/drive_c/users/satoru/Documents"
echo "somebody else's" > "$prefix/drive_c/users/satoru/Documents/configuration_system.lua"
out=$(bash migrate-prefix-user.sh "$prefix" satoru 2>&1); code=$?
check "two profiles at once is refused" "$([ "$code" != 0 ] && echo refused)" refused
check "  and it names both" "$(echo "$out" | grep -c 'satoru')" 1
check "  and nothing was moved" \
    "$([ -d "$prefix/drive_c/users/crossover" ] && echo yes || echo no)" yes
check "  and nothing was rewritten" \
    "$(grep -c '"USERNAME"="crossover"' "$prefix/user.reg")" 1

# ------------------------------------- a half-migrated prefix finishes itself

# The directory was renamed by hand (or an interrupted run), the registry was
# not. Leaving that alone is the same silent data loss, so it is completed.
prefix="$work/half"
make_old_prefix "$prefix"
mv "$prefix/drive_c/users/crossover" "$prefix/drive_c/users/satoru"
out=$(bash migrate-prefix-user.sh "$prefix" satoru 2>&1); code=$?
check "a half-migrated prefix is finished" "$code" 0
check "  the registry is rewritten" \
    "$(grep -ci 'users\\\\crossover' "$prefix"/*.reg | awk -F: '{s+=$2} END {print s+0}')" 0

# ------------------------------------------------- a fresh prefix is skipped

prefix="$work/fresh"
mkdir -p "$prefix/drive_c/users/satoru" "$prefix/dosdevices"
printf 'WINE REGISTRY Version 2\n' > "$prefix/user.reg"
printf 'WINE REGISTRY Version 2\n' > "$prefix/system.reg"
out=$(bash migrate-prefix-user.sh "$prefix" satoru 2>&1); code=$?
check "a prefix made by the new engine is left alone" "$code" 0
check "  and nothing is said about it" "$out" ""

# --------------------------------- a wineserver already holding the prefix

# aoe4.sh's own use case: relaunching while Steam is already up forwards the
# applaunch to the running session instead of starting a new one, so the
# wineserver check must not fire on a prefix that needs no migration - only on
# one it is actually about to rename or rewrite.
prefix="$work/wineserver-unmigrated"
make_old_prefix "$prefix"
install_wineserver_shim "$prefix"
out=$(PATH="$work/bin:$PATH" bash migrate-prefix-user.sh "$prefix" satoru 2>&1); code=$?
check "a running wineserver blocks an unmigrated prefix" "$code" 3
check "  and nothing was moved" \
    "$([ -d "$prefix/drive_c/users/crossover" ] && echo yes || echo no)" yes
check "  and nothing was rewritten" \
    "$(grep -c '"USERNAME"="crossover"' "$prefix/user.reg")" 1

prefix="$work/wineserver-migrated"
make_old_prefix "$prefix"
bash migrate-prefix-user.sh "$prefix" satoru >/dev/null 2>&1
install_wineserver_shim "$prefix"
out=$(PATH="$work/bin:$PATH" bash migrate-prefix-user.sh "$prefix" satoru 2>&1); code=$?
check "a running wineserver does not block an already-migrated prefix" "$code" 0
check "  and says nothing" "$out" ""
rm -rf "$work/bin"

# ------------------------------- an engine that still uses the old name

# The name comes from the engine, and a pack that ships an older engine (the
# ones currently staged: AoE4 cf465d4, Prime World 711c6fc) declares none.
# Renaming under such an engine would cause the loss this script exists to
# prevent: the engine would look for crossover, find nothing, and build an
# empty profile beside the renamed one. So without a name, nothing happens.
prefix="$work/no-engine-name"
make_old_prefix "$prefix"
out=$(bash migrate-prefix-user.sh "$prefix" 2>&1); code=$?
check "no profile name from the engine means no migration" "$code" 0
check "  and it is silent about it" "$out" ""
check "  and the old profile is untouched" \
    "$([ -d "$prefix/drive_c/users/crossover" ] && echo yes || echo no)" yes
check "  and the registry is untouched" \
    "$(grep -c '"USERNAME"="crossover"' "$prefix/user.reg")" 1

out=$(bash migrate-prefix-user.sh "$prefix" "" 2>&1); code=$?
check "an empty profile name is the same as none" "$code" 0
check "  still untouched" \
    "$([ -d "$prefix/drive_c/users/crossover" ] && echo yes || echo no)" yes

out=$(bash migrate-prefix-user.sh "$prefix" crossover 2>&1); code=$?
check "an engine that declares the old name changes nothing" "$code" 0
check "  still untouched" \
    "$([ -d "$prefix/drive_c/users/crossover" ] && echo yes || echo no)" yes

out=$(bash migrate-prefix-user.sh "$prefix" "../escape" 2>&1); code=$?
check "a profile name that is not one is refused" "$([ "$code" != 0 ] && echo refused)" refused
check "  and nothing was moved" \
    "$([ -d "$prefix/drive_c/users/crossover" ] && echo yes || echo no)" yes

exit "$fail"
