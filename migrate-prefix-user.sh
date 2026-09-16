#!/bin/bash
# Rename the Windows profile inside an existing prefix from crossover to satoru.
#
# Our engine descends from a CrossOver tree whose GetUserName always answered
# "crossover", so that a bottle kept working after it was copied to another
# machine. We kept the behaviour and changed the name. A prefix made before that
# change holds C:\users\crossover, and every shell folder, the profile in
# ProfileList and the USERNAME value point into it. Opened by the new engine
# without this migration, such a prefix quietly grows a second, empty profile:
# the game starts, finds no settings, no saves and no screenshots, and writes
# new ones next to the old. Nothing announces the loss.
#
# So this runs before the engine is allowed near an existing prefix - from
# setup.sh on installation, and from aoe4.sh on every launch, where the cost of
# an already-migrated prefix is one directory test.
#
# The name to migrate to is not written here: it is whatever the engine in this
# home declares in Engine/.profile-user, and without that file nothing happens
# at all. Renaming the profile under an engine that still answers "crossover"
# would cause exactly the loss described above, with this script as the cause -
# the engine would find no profile under the name it uses and build an empty one
# beside the renamed original. Packs that ship an older engine therefore carry
# this script harmlessly.
#
# It is deliberately narrow: it renames one directory and rewrites the paths
# that name it. Where it cannot be sure which profile holds the player's things
# it refuses and says so, rather than picking one and discarding the other.
set -u

OLD_USER=crossover

dry=0
[ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
prefix="${1:-${WINEPREFIX:-}}"
NEW_USER="${2:-}"

[ -n "$prefix" ] || { echo "usage: migrate-prefix-user.sh [--dry-run] <prefix> <profile-name>" >&2; exit 2; }

# The engine does not declare a profile name, so it is an engine that still uses
# the old one. Nothing to do, and saying anything would be noise on every launch.
[ -n "$NEW_USER" ] || exit 0
[ "$NEW_USER" = "$OLD_USER" ] && exit 0
case "$NEW_USER" in
    *[!A-Za-z0-9._-]*|.|..)
        echo "migrate-prefix-user: $NEW_USER is not a usable profile name" >&2; exit 2 ;;
esac

# No prefix yet, or a directory that is not one: the new engine will create it
# with the new name and there is nothing to carry over.
[ -d "$prefix" ] || exit 0
[ -f "$prefix/system.reg" ] || exit 0

users="$prefix/drive_c/users"
old_dir="$users/$OLD_USER"
new_dir="$users/$NEW_USER"

reg_has_old=0
for reg in "$prefix"/*.reg; do
    [ -f "$reg" ] || continue
    if /usr/bin/grep -qi 'users\\\\'"$OLD_USER" "$reg" || /usr/bin/grep -q '"USERNAME"="'"$OLD_USER"'"' "$reg"; then
        reg_has_old=1
        break
    fi
done

# Nothing to migrate: leave before the checks below, so that a prefix already
# named satoru costs one directory test and never refuses. This runs on every
# launch, and a game that is already up must not be answered with "close the
# game first" for a prefix there is no reason to touch.
[ -d "$old_dir" ] || [ "$reg_has_old" = 1 ] || exit 0

# A prefix still open by a wineserver would have the registry rewritten under
# it and would then write its own copy back over ours.
prefix_real="$(cd "$prefix" && pwd -P)"
for pid in $(pgrep -f 'wineserver' 2>/dev/null); do
    env_line="$(ps eww -o command= -p "$pid" 2>/dev/null)"
    case " $env_line " in
        *" WINEPREFIX=$prefix_real "*|*" WINEPREFIX=$prefix "*)
            echo "migrate-prefix-user: $prefix is open by wineserver (pid $pid); close the game first" >&2
            exit 3 ;;
    esac
done

# Both profiles present. Either could be the one with the player's things in it,
# and merging them is not something a script should decide.
if [ -d "$old_dir" ] && [ -e "$new_dir" ]; then
    echo "migrate-prefix-user: $prefix has both $OLD_USER and $NEW_USER profiles; move the one you want to keep to $new_dir and delete the other" >&2
    exit 4
fi

if [ "$dry" = 1 ]; then
    [ -d "$old_dir" ] && echo "would rename $old_dir -> $new_dir"
    [ "$reg_has_old" = 1 ] && echo "would rewrite the profile paths in $prefix/*.reg"
    exit 0
fi

if [ -d "$old_dir" ]; then
    mv "$old_dir" "$new_dir" || {
        echo "migrate-prefix-user: cannot rename $old_dir" >&2; exit 5; }
fi

if [ "$reg_has_old" = 1 ]; then
    # Only the profile path and the user name. "CrossOver" also appears as a
    # product name in DisplayName values, and renaming that would be a lie
    # about which program installed what.
    for reg in "$prefix"/*.reg; do
        [ -f "$reg" ] || continue
        /usr/bin/perl -pi -e '
            s/(C:\\\\users\\\\)'"$OLD_USER"'/${1}'"$NEW_USER"'/gi;
            s/("USERNAME"=")'"$OLD_USER"'(")/${1}'"$NEW_USER"'${2}/g;
        ' "$reg" || { echo "migrate-prefix-user: cannot rewrite $reg" >&2; exit 6; }
    done
fi

echo "The prefix's Windows profile moved from $OLD_USER to $NEW_USER: $prefix"
