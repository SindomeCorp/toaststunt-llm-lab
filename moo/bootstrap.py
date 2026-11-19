#!/usr/bin/env python3
"""Provision the dedicated MCP programmer on a fresh stock ToastCore."""

import json
import os
from pathlib import Path
import re
import secrets
import time

from install import BOOTSTRAP, Console, install


ROOT = Path(__file__).resolve().parent.parent
STATE = ROOT / "state"
HOST = "127.0.0.1"


def connect(port, password):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        try:
            return Console(HOST, port, "Wizard", password)
        except OSError:
            time.sleep(0.2)
    raise RuntimeError(f"ToastCore did not become ready on port {port}")


def main():
    os.umask(0o077)
    port = int((STATE / "port").read_text())
    credential_path = STATE / "credentials.json"
    complete = STATE / "mcp-installed"
    if complete.exists():
        if not credential_path.exists():
            raise RuntimeError("Restore the lab credentials before continuing.")
        return
    if not credential_path.exists():
        credentials = {
            "wizard_password": secrets.token_hex(24),
            "programmer_user": "LabProgrammer",
            "programmer_password": secrets.token_hex(24),
        }
        pending = credential_path.with_suffix(".tmp")
        pending.write_text(json.dumps(credentials, indent=2) + "\n")
        pending.replace(credential_path)
    credentials = json.loads(credential_path.read_text())

    # A saved checkpoint can contain the generated password after an interrupted setup.
    wizard_password = credentials["wizard_password"]
    for password in (wizard_password, ""):
        wizard = connect(port, password)
        try:
            wizard.message(
                f';;if (player.wizard) notify(player, "{BOOTSTRAP}true"); endif',
                BOOTSTRAP, timeout=2,
            )
        except (TimeoutError, ConnectionError):
            wizard.socket.close()
            continue
        break
    else:
        raise RuntimeError("Wizard login failed. Use the manual feature setup for an existing database.")

    with wizard:
        player_name = json.dumps(credentials["programmer_user"])
        new_password = json.dumps(credentials["programmer_password"])
        admin_password = json.dumps(wizard_password)
        account = wizard.evaluate(
            f'player.password = $login:encrypt_password({admin_password}); '
            'player.last_password_time = time(); '
            f'p = $player_db:find({player_name}); '
            'if (!valid(p)) p = create($prog); '
            f'p.name = {player_name}; p.aliases = {{p.name}}; '
            'p.programmer = 1; set_player_flag(p, 1); p.owner = p; '
            '$player_db:insert(p.name, p); move(p, $player_start); '
            'elseif (!p.programmer || p.wizard || p.owner != p) '
            'raise(E_PERM, "An unrelated account has the configured programmer name."); endif '
            f'p.password = $login:encrypt_password({new_password}); p.last_password_time = time(); '
            f'notify(player, "{BOOTSTRAP}" + generate_json(tostr(p)));'
        )
        if not isinstance(account, str) or not re.fullmatch(r"#[0-9]+", account):
            raise RuntimeError("Unable to identify the lab programmer.")
        attached = wizard.evaluate(
            f'for f in ({account}.features) '
            f'if (valid(f) && `f.mcp_programmer == {account} && f.name == "MOO MCP Feature" ! E_PROPNF, E_PERM => 0\') '
            f'notify(player, "{BOOTSTRAP}true"); return; endif endfor '
            f'notify(player, "{BOOTSTRAP}false");'
        )
        if not attached:
            install(wizard, account)

    with Console(HOST, port, credentials["programmer_user"], credentials["programmer_password"]) as programmer:
        response = programmer.request("hello", {})
        if not response["ok"] or response["result"]["programmer"] != account:
            raise RuntimeError("The new programmer did not reach its installed MCP feature.")
    with Console(HOST, port, "Wizard", wizard_password) as wizard:
        checkpoint = STATE / "toastcore.db.new"
        old_inode = checkpoint.stat().st_ino if checkpoint.exists() else None
        wizard.evaluate(f'dump_database(); notify(player, "{BOOTSTRAP}true");')
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if checkpoint.exists() and checkpoint.stat().st_ino != old_inode:
                complete.write_text(account + "\n")
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("The initial checkpoint did not complete.")


if __name__ == "__main__":
    main()
