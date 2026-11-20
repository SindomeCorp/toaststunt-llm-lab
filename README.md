# ToastStunt LLM Lab

Run a persistent, loopback-only ToastStunt MOO and give Codex a dedicated programmer login through MCP. A stock ToastCore database is the default. You can supply another ToastStunt database and install the feature on it if it has compatible feature dispatch and `@program`.

## Quick start on Ubuntu or Debian

Install the [ToastStunt build prerequisites](https://github.com/lisdude/toaststunt#build-instructions), plus Git, Python 3.9+, Node.js 22+, npm, and a working systemd user manager. Then clone and run setup:

```sh
git clone https://github.com/SindomeCorp/toaststunt-llm-lab.git
cd toaststunt-llm-lab
./setup.sh --register-codex
```

The setup script fetches the latest commit from the default branch of [ToastStunt](https://github.com/lisdude/toaststunt), [ToastCore](https://github.com/lisdude/toastcore), and [SindomeCorp/moo-mcp](https://github.com/SindomeCorp/moo-mcp) into `vendor/`. It builds ToastStunt, seeds the database, installs and enables the user service, and creates a non-wizard `LabProgrammer` with the MCP feature.

> **Optional wizard access:** Log in as `Wizard` and set the `LabProgrammer` account's `.wizard` property to `1` if you want it to be a wizard. The MCP connection will then have wizard privileges.

Setup generates both login passwords in the private `state/credentials.json` file, checkpoints the installation, verifies MCP, and registers `toaststunt_llm_lab` in Codex. Omit `--register-codex` to skip modifying your Codex user configuration. You can merge the generated `config.toml` into that configuration later.

Rerunning setup fetches the latest versions again, rebuilds the engine, refreshes MCP dependencies when its revision changes, and restarts the service. Existing world data and accounts are preserved; the latest ToastCore database is used only when seeding a fresh world. Setup stops if a vendor checkout has local source changes.

The lab launcher runs the standard `moo-mcp/src/index.js` entry point with the shipped `config/toaststunt-llm-lab.tools.json` profile. To test a different committed server revision, set `MOO_MCP_SOURCE` to a repository URL or absolute checkout path and `MOO_MCP_REVISION` to its commit SHA before running setup.

The MOO listens on `127.0.0.1:7778` by default. Set `MOO_PORT` on the first install to select another port. Start a fresh Codex session on the machine hosting the lab to load the registration. `python3 verify-mcp.py` exercises the local MCP launcher without using a model. To administer the game, connect locally as `Wizard` with the generated wizard password.

```sh
systemctl --user status toaststunt-llm-lab.service
journalctl --user -u toaststunt-llm-lab.service -f
systemctl --user restart toaststunt-llm-lab.service
```

For startup at boot before login, enable lingering for the service account with `loginctl enable-linger "$USER"` if the host requires it.

## Run a second lab on the same host

Give a fresh checkout a distinct instance name and port so both the systemd service and the Codex entry remain separate.

```sh
TOASTSTUNT_LAB_INSTANCE=test MOO_PORT=7789 ./setup.sh --register-codex
```

This uses `toaststunt-llm-lab-test.service` and registers `toaststunt_llm_lab_test`. The checkout remembers its instance name for subsequent setup runs and engine updates. Use the instance's unit name in systemctl commands.

## Checkpoints and alternate databases

The engine opens `state/toastcore.db` and publishes each completed save as `state/toastcore.db.new`. On startup, `restart.sh` keeps a copy of the prior boot database in `state/toastcore.db.old`, atomically promotes the completed checkpoint, then runs the engine in the foreground. A clean systemd stop gives the engine time to save. After a crash, the last completed checkpoint is recovered. Back up the database separately if you need more than the previous boot file.

To start a fresh lab from a different ToastStunt database, provide a consistent checkpoint as the seed. The lab uses the same runtime filename regardless of the seed filename.

```sh
MOO_PORT=7788 MOO_SEED_DB=/absolute/path/to/other-world.db ./setup.sh --server-only
```

To switch an existing lab, first use `systemctl --user stop toaststunt-llm-lab.service` and archive the entire `state/` directory under an ignored path outside this repository. Then run the alternate seed command. Keeping each world's checkpoint files and credentials together prevents an old `.db.new` from being loaded into the wrong world. Preserve the archived directory to switch back with the service stopped.

## Install the MOO feature manually

The automatic wizard bootstrap is for the bundled stock ToastCore seed. For an existing database, create or select a non-wizard programmer who is in a valid room and whose password you control. Log in with wizard permissions for the feature installation.

The [full stock ToastCore install transcript](moo/install.moo) contains the creation command, verb metadata, interactive `@program` commands and complete source, and feature attachment. Substitute the target programmer object for `{{PROGRAMMER}}`. Run the first command and use the object number it returns for `{{FEATURE}}` in the remaining commands. Run the commands in order, allowing each `@program` session to complete before issuing the next command. Regenerate the transcript from the canonical [verb source](moo/feature.moo) with `python3 moo/install.py --transcript > moo/install.moo`.

The same install can run over the loopback connection without manual substitutions:

```bash
read -rs -p 'Wizard password: ' MOO_PASSWORD; echo
export MOO_PASSWORD
python3 moo/install.py --port 7788 --username Wizard --programmer '#123'
unset MOO_PASSWORD
python3 configure-mcp.py
python3 verify-mcp.py
codex mcp add toaststunt_llm_lab -- python3 "$PWD/launch-mcp.py"
```

Use the actual port and programmer object. `configure-mcp.py` prompts for the programmer login and stores it locally. The bridge uses the programmer's authority. The standard feature leaves the separate structured eval tool disabled, and raw commands are subject to the programmer's ordinary MOO privileges. Source comes from the repository checkout so the installed code can be reviewed and reproduced.

## Update ToastStunt

```sh
./update-toaststunt.sh          # Fetch and build upstream master
./update-toaststunt.sh v2.8.0   # Or build a selected upstream tag or commit
```

Each revision builds in its own directory. The service switches to the built binary only after the build succeeds, then restarts and loads the newest checkpoint. Before crossing engine versions, keep a separate database snapshot for rollback. An older engine may be unable to load a checkpoint saved by a newer engine.

## Manual runtime layout on other operating systems

Follow the [ToastStunt build instructions](https://github.com/lisdude/toaststunt#build-instructions) for your OS. Keep the same layout or adjust the launch paths for your service manager.

| Path | Contents |
| --- | --- |
| `state/engine` | Executable or symlink to your ToastStunt `moo` binary |
| `state/toastcore.db` | A copy of your starting database, such as [stock ToastCore](https://github.com/lisdude/toastcore) |
| `state/toastcore.db.new` | Checkpoint output, created by the engine |
| `state/port` | One line containing the chosen local port |
| `state/node` | One line containing the absolute path to the Node executable |
| `vendor/moo-mcp/` | [MCP server checkout](https://github.com/SindomeCorp/moo-mcp) with the lab profile and dependencies installed via `npm ci` |

Make `state/` private to the service account. On Linux the supplied restart script implements checkpoint rotation. On other systems, use your service manager's equivalent rotation before launching the engine in the foreground. The engine invocation is:

```sh
./state/engine -O --no-ipv6 -4 127.0.0.1 state/toastcore.db state/toastcore.db.new 7778
```

Then install the MOO feature and configure MCP using the manual steps above. The tracked `.example` files show the service, Codex, and seed/update configuration. Generated configuration, credentials, vendor checkouts, DBs, and logs are ignored by Git.
