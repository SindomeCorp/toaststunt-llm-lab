#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

remove=false
case "${1:-}" in
    '') ;;
    --remove) remove=true ;;
    *) echo "Usage: $0 [--remove]" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
    echo "Usage: $0 [--remove]" >&2
    exit 2
fi
if [[ ! -d state ]]; then
    echo "No lab state found. There is no service to disable for this checkout."
    exit 0
fi
umask 077
exec 8>state/setup.lock
flock -n 8
instance=$(cat state/instance 2>/dev/null || true)
if [[ -n $instance && ! $instance =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "Invalid saved instance name." >&2
    exit 1
fi
unit=toaststunt-llm-lab${instance:+-$instance}.service
unit_file="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$unit"
if [[ ! -f $unit_file ]]; then
    echo "No installed $unit found for this user."
    exit 0
fi
installed_root=$(sed -n 's/^WorkingDirectory=//p' "$unit_file")
if [[ $installed_root != "${PWD//%/%%}" ]]; then
    echo "$unit belongs to another directory: $installed_root" >&2
    exit 1
fi

# An explicit stop suppresses Restart=on-failure as well as stopping the MOO.
systemctl --user disable --now "$unit"
if [[ $remove == true ]]; then
    rm -- "$unit_file"
    systemctl --user daemon-reload
    echo "Removed $unit."
else
    echo "Stopped $unit and disabled automatic startup."
fi
echo "World data, credentials, and the Codex registration were kept."
