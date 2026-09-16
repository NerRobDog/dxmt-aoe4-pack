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
# It is deliberately narrow: it renames one directory and rewrites the paths
# that name it. Where it cannot be sure which profile holds the player's things
# it refuses and says so, rather than picking one and discarding the other.
set -u

OLD_USER=crossover
NEW_USER=satoru

dry=0
[ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
prefix="${1:-${WINEPREFIX:-}}"

[ -n "$prefix" ] || { echo "usage: migrate-prefix-user.sh [--dry-run] <prefix>" >&2; exit 2; }

# No prefix yet, or a directory that is not one: the new engine will create it
# with the new name and there is nothing to carry over.
[ -d "$prefix" ] || exit 0
[ -f "$prefix/system.reg" ] || exit 0

users="$prefix/drive_c/users"
old_dir="$users/$OLD_USER"
new_dir="$users/$NEW_USER"

# Both profiles present. Either could be the one with the player's things in it,
# and merging them is not something a script should decide. Checked before the
# "nothing to do" exit below: two profiles is never nothing to do, migrated or
# not.
if [ -d "$old_dir" ] && [ -e "$new_dir" ]; then
    echo "migrate-prefix-user: $prefix has both $OLD_USER and $NEW_USER profiles; move the one you want to keep to $new_dir and delete the other" >&2
    exit 4
fi

reg_has_old=0
for reg in "$prefix"/*.reg; do
    [ -f "$reg" ] || continue
    if /usr/bin/grep -qi 'users\\\\'"$OLD_USER" "$reg" || /usr/bin/grep -q '"USERNAME"="'"$OLD_USER"'"' "$reg"; then
        reg_has_old=1
        break
    fi
done

[ -d "$old_dir" ] || [ "$reg_has_old" = 1 ] || exit 0

# A prefix still open by a wineserver would have the registry rewritten under
# it and would then write its own copy back over ours. Checked only once there
# is real work to do: aoe4.sh relaunches into a prefix Steam already holds
# (the applaunch is forwarded to the running session), and an already-migrated
# prefix must not be refused just because Steam is up.
prefix_real="$(cd "$prefix" && pwd -P)"
for pid in $(pgrep -f 'wineserver' 2>/dev/null); do
    env_line="$(ps eww -o command= -p "$pid" 2>/dev/null)"
    case " $env_line " in
        *" WINEPREFIX=$prefix_real "*|*" WINEPREFIX=$prefix "*)
            echo "migrate-prefix-user: $prefix is open by wineserver (pid $pid); close the game first" >&2
            exit 3 ;;
    esac
done

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
