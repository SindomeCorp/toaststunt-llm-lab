#!/usr/bin/env python3
"""Set the bridge login for a world with an existing MCP feature."""

import getpass
import json
import os
from pathlib import Path


def main():
    path = Path(__file__).resolve().parent / "state" / "credentials.json"
    credentials = json.loads(path.read_text()) if path.exists() else {}
    username = input("MOO programmer login: ").strip()
    password = getpass.getpass("MOO programmer password: ")
    if not username or any(char.isspace() for char in username + password):
        raise SystemExit("The MOO login and password must each fit in one word.")
    credentials.update(programmer_user=username, programmer_password=password)
    os.umask(0o077)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(credentials, indent=2) + "\n")
    temporary.replace(path)


if __name__ == "__main__":
    main()
