#!/usr/bin/env bash
set -euo pipefail
if [[ -n ${MOO_SEED_DB:-} && $MOO_SEED_DB != /* ]]; then
    MOO_SEED_DB=$PWD/$MOO_SEED_DB
fi
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
lab_path=$PWD
umask 077

server_only=false
register_codex=false
for option in "$@"; do
    case "$option" in
        --server-only) server_only=true ;;
        --register-codex) register_codex=true ;;
        *) echo "Usage: $0 [--server-only | --register-codex]" >&2; exit 2 ;;
    esac
done
if [[ $server_only == true && $register_codex == true ]]; then
    echo "Install and verify the MCP feature before registering a server-only world." >&2
    exit 2
fi
if [[ $register_codex == true ]]; then
    command -v codex >/dev/null || { echo "Codex is missing from PATH." >&2; exit 1; }
fi

for dependency in git cmake npm node python3 systemctl flock; do
    command -v "$dependency" >/dev/null || {
        echo "Missing dependency: $dependency. See README.md." >&2
        exit 1
    }
done
systemctl --user show-environment >/dev/null
mkdir -p vendor state
exec 8>state/setup.lock
flock -n 8

instance=${TOASTSTUNT_LAB_INSTANCE:-}
if [[ -f state/instance ]]; then
    saved_instance=$(cat state/instance)
    if [[ ${TOASTSTUNT_LAB_INSTANCE+x} && $instance != "$saved_instance" ]]; then
        echo "The instance name is fixed after the first setup." >&2
        exit 1
    fi
    instance=$saved_instance
elif [[ -e state/toastcore.db && -n $instance ]]; then
    echo "Set TOASTSTUNT_LAB_INSTANCE in a fresh checkout." >&2
    exit 1
fi
if [[ -n $instance && ! $instance =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "TOASTSTUNT_LAB_INSTANCE must contain lowercase letters or digits separated by hyphens." >&2
    exit 1
fi
unit=toaststunt-llm-lab${instance:+-$instance}.service
codex_name=toaststunt_llm_lab${instance:+_${instance//-/_}}
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
if [[ -f "$unit_dir/$unit" ]]; then
    installed_root=$(sed -n 's/^WorkingDirectory=//p' "$unit_dir/$unit")
    if [[ "$installed_root" != "${lab_path//%/%%}" ]]; then
        echo "$unit already belongs to another directory: $installed_root" >&2
        exit 1
    fi
fi
printf '%s\n' "$instance" > state/instance

checkout() {
    local name=$1 url=$2 revision=$3 update=${4:-false} dir="vendor/$1"
    if [[ ! -d "$dir/.git" ]]; then
        git clone --no-checkout -- "$url" "$dir"
        git -C "$dir" checkout --detach "$revision"
    elif [[ -n $(git -C "$dir" status --porcelain --untracked-files=no) ]]; then
        echo "$dir has source changes. Inspect it before continuing." >&2
        exit 1
    elif [[ $(git -C "$dir" rev-parse --verify HEAD) != "$revision" ]]; then
        if [[ $update != true ]]; then
            echo "$dir differs from the pinned revision. Inspect it before continuing." >&2
            exit 1
        fi
        if ! git -C "$dir" cat-file -e "$revision^{commit}" 2>/dev/null; then
            git -C "$dir" fetch --no-tags -- "$url" "$revision"
        fi
        git -C "$dir" checkout --detach "$revision"
    fi
}

engine_revision=2152ad4f6b57e82989c4fa110fc1ce70278f0cf7
if [[ -s state/engine-revision ]]; then
    engine_revision=$(cat state/engine-revision)
fi
checkout toaststunt https://github.com/lisdude/toaststunt.git "$engine_revision"
checkout toastcore https://github.com/lisdude/toastcore.git 4b6a94d45e7bc5e207682204cd8047992c0af8e3
moo_mcp_source=${MOO_MCP_SOURCE:-https://github.com/SindomeCorp/moo-mcp.git}
moo_mcp_revision=${MOO_MCP_REVISION:-c5d2536e3b8396b6f653bb8477c1ab8dc75a4978}
if [[ ! $moo_mcp_revision =~ ^[0-9a-f]{40}$ ]]; then
    echo "MOO_MCP_REVISION must be a full commit SHA." >&2
    exit 1
fi
checkout moo-mcp "$moo_mcp_source" "$moo_mcp_revision" true
if [[ ! -f vendor/moo-mcp/config/toaststunt-llm-lab.tools.json ]]; then
    echo "The selected moo-mcp revision does not contain the ToastStunt lab profile." >&2
    exit 1
fi
./build-engine.sh "$engine_revision"
if [[ ! -d vendor/moo-mcp/node_modules/@modelcontextprotocol/sdk ]] ||
    [[ $(cat state/moo-mcp-deps 2>/dev/null || true) != "$moo_mcp_revision" ]]; then
    npm --prefix vendor/moo-mcp ci --no-audit --no-fund
    printf '%s\n' "$moo_mcp_revision" > state/moo-mcp-deps
fi
command -v node > state/node

if [[ ! -f state/port ]]; then
    python3 - "${MOO_PORT:-7778}" <<'PY'
import socket
import sys
from pathlib import Path

port = int(sys.argv[1])
if not 1024 <= port <= 65535:
    sys.exit("MOO_PORT must be between 1024 and 65535.")
try:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", port))
except OSError as error:
    sys.exit(f"Port {port} is unavailable. Set MOO_PORT to an unused port. {error}")
Path("state/port").write_text(f"{port}\n")
PY
elif [[ -n ${MOO_PORT:-} && $MOO_PORT != "$(cat state/port)" ]]; then
    echo "This lab already uses port $(cat state/port)." >&2
    exit 1
fi

if [[ -e state/toastcore.db && -n ${MOO_SEED_DB:-} ]]; then
    echo "To use a different seed, stop the service and archive state/ first." >&2
    exit 1
fi
# Seed only a fresh world. A missing boot DB on an existing lab needs recovery.
if [[ ! -e state/toastcore.db ]]; then
    if [[ -e state/toastcore.db.new || -e state/toastcore.db.old || -e state/credentials.json ]]; then
        echo "Database files indicate an existing lab. Recover the boot DB before restarting." >&2
        exit 1
    fi
    if [[ -n ${MOO_SEED_DB:-} && $server_only == false ]]; then
        echo "Use --server-only to seed an existing database, then follow the manual MCP steps." >&2
        exit 1
    fi
    install -m 600 "${MOO_SEED_DB:-vendor/toastcore/toastcore.db}" state/toastcore.db.tmp
    mv -- state/toastcore.db.tmp state/toastcore.db
fi

python3 - "$lab_path" "$unit" "$codex_name" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
if any(char in str(root) for char in "\r\n"):
    sys.exit("The lab path must fit on one line.")
unit = root / sys.argv[2]
template = (root / "toaststunt-llm-lab.service.example").read_text()
source = template.replace("@LAB_PATH@", str(root).replace("%", "%%"))
unit.write_text(source)
config = root / "config.toml"
template = config.with_suffix(".toml.example").read_text()
template = template.replace("[mcp_servers.toaststunt_llm_lab]", f"[mcp_servers.{sys.argv[3]}]")
config.write_text(template.replace(
    '"/absolute/path/to/toaststunt-llm-lab/launch-mcp.py"',
    json.dumps(str(root / "launch-mcp.py"), ensure_ascii=False),
))
PY

install -d "$unit_dir"
install -m 600 "$unit" "$unit_dir/$unit"
systemctl --user daemon-reload
if [[ $server_only == true && ! -e state/mcp-installed ]]; then
    touch state/server-only
fi
systemctl --user enable --now "$unit"
if [[ $server_only == false ]]; then
    if [[ -e state/server-only ]]; then
        echo "This lab used --server-only. Follow the manual MCP setup in README.md." >&2
        exit 1
    fi
    python3 moo/bootstrap.py
    python3 verify-mcp.py
    if [[ $register_codex == true ]]; then
        codex mcp add "$codex_name" -- python3 "$lab_path/launch-mcp.py"
    fi
fi

echo "MOO is listening at 127.0.0.1:$(cat state/port)."
if [[ $register_codex == false ]]; then
    echo "Use $lab_path/config.toml to register the bridge after the feature is installed."
fi
