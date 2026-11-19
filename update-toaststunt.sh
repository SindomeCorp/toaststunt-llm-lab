#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
umask 077
vendor=vendor/toaststunt
test -d "$vendor/.git"
test -L state/engine
exec 8>state/setup.lock
flock -n 8
instance=$(cat state/instance 2>/dev/null || true)
unit=toaststunt-llm-lab${instance:+-$instance}.service

if [[ -n $(git -C "$vendor" status --porcelain --untracked-files=no) ]]; then
    echo "Commit or set aside ToastStunt source changes before updating." >&2
    exit 1
fi
if (( $# > 1 )); then
    echo "Usage: $0 [commit-or-tag]" >&2
    exit 2
fi
git -C "$vendor" fetch --tags origin
revision=$(git -C "$vendor" rev-parse --verify --end-of-options "${1:-origin/master}^{commit}")
git -C "$vendor" checkout --detach "$revision"
printf '%s\n' "$revision" > state/engine-revision
./build-engine.sh "$revision"
systemctl --user restart "$unit"
