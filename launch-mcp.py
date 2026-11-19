#!/usr/bin/env python3
"""Launch the local stdio bridge with the lab programmer's credentials."""

import json
import os
from pathlib import Path

root = Path(__file__).resolve().parent
state = root / "state"
node = (state / "node").read_text().strip()
credentials = json.loads((state / "credentials.json").read_text())
bridge = root / "vendor" / "moo-mcp"
profile = bridge / "config" / "toaststunt-llm-lab.tools.json"
if not profile.is_file():
    raise SystemExit("The moo-mcp checkout is missing the lab profile. Run setup.sh to update it.")

environment = {
    **os.environ,
    "moo-hostname": "127.0.0.1",
    "moo-port": (state / "port").read_text().strip(),
    "moo-user": credentials["programmer_user"],
    "moo-password": credentials["programmer_password"],
    "moo-tools-config": str(profile),
    "mcp-mode": "stdio",
}
os.chdir(state)
os.execve(node, [node, str(bridge / "src" / "index.js")], environment)
