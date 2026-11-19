#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
umask 077

# A second copy of the wrapper must not rotate files under a running MOO.
exec 9>state/server.lock
flock -n 9
port=$(cat state/port)
db=state/toastcore.db
checkpoint=$db.new
test -s "$db"
if [ -e "$checkpoint" ]; then
    test -s "$checkpoint"
    # Keep the boot DB in place until its replacement is ready to rename.
    cp --reflink=auto -- "$db" "$db.old.tmp"
    mv -fT -- "$db.old.tmp" "$db.old"
    mv -fT -- "$checkpoint" "$db"
fi

exec ./state/engine -O --no-ipv6 -4 127.0.0.1 "$db" "$checkpoint" "$port"
