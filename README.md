# ToastStunt LLM Lab

> **Only need an MCP server?** If you already have a MOO and do not need this repository's ToastStunt build, database setup, and background service, use [SindomeCorp/moo-mcp](https://github.com/SindomeCorp/moo-mcp) directly. Configure it for your MOO, the tools you need, and your preferred agent.

This repository sets up a local ToastStunt MOO with a stock ToastCore database and gives Codex a dedicated programmer login through MCP. The MOO listens only on the local machine. You can also supply an existing ToastStunt database if it supports compatible feature dispatch and `@program`.

## Quick start on Ubuntu or Debian

Install the [ToastStunt build prerequisites](https://github.com/lisdude/toaststunt#build-instructions), plus Git, Python 3.9+, Node.js 22+, npm, and `flock` (provided by `util-linux`). You need a working systemd user manager. To register the MCP server automatically, the Codex CLI must also be available as `codex` in your terminal.

Clone the repository and run setup as your normal user, without `sudo`:

```sh
git clone https://github.com/SindomeCorp/toaststunt-llm-lab.git
cd toaststunt-llm-lab
./setup.sh --register-codex
```

Unless stated otherwise, run the commands in this README from the repository directory. Keep the checkout in this location after setup: the service and MCP registration use absolute paths into it.

Setup fetches the latest commit from the default branch of [ToastStunt](https://github.com/lisdude/toaststunt), [ToastCore](https://github.com/lisdude/toastcore), and [SindomeCorp/moo-mcp](https://github.com/SindomeCorp/moo-mcp) into `vendor/`. It builds ToastStunt, seeds the database, installs and starts the user service, enables startup at login, and creates a non-wizard `LabProgrammer` with the MCP feature.

> **Optional wizard access:** Log in as `Wizard` and set the `LabProgrammer` account's `.wizard` property to `1` if you want it to be a wizard. The MCP connection will then have wizard privileges.

Setup updates the default Wizard password and stores both the new Wizard password and the new LabProgrammer password in the private `state/credentials.json` file. It checkpoints the installation, verifies MCP, and, with `--register-codex`, registers `toaststunt_llm_lab` in Codex. Omit `--register-codex` to skip modifying your Codex user configuration. You can merge the generated `config.toml` into that configuration later.

> **Wizard login:** Run `cat state/credentials.json` to get the new Wizard password. The default blank password no longer works after setup. Keep this file private; it contains both login passwords.

The MOO listens on `127.0.0.1:7778` by default. To choose a different port, set `MOO_PORT` on the first setup run, for example `MOO_PORT=7788 ./setup.sh --register-codex`. The checkout remembers this port.

## Verify the installation and log in

Check the service and test the MCP connection:

```sh
systemctl --user status toaststunt-llm-lab.service
python3 verify-mcp.py
```

The verifier checks an MCP handshake, the tool catalog, and access to the installed feature's source. It does not use a model. Start a fresh Codex chat on the machine hosting the lab and ask it to use `toaststunt_llm_lab` to inspect the world.

For a direct login, connect a MOO client to `127.0.0.1:7778`, or your chosen port. Enter one of these commands in the MOO client, replacing the password placeholder with the corresponding value from `state/credentials.json`:

```text
connect Wizard YOUR_WIZARD_PASSWORD
connect LabProgrammer YOUR_PROGRAMMER_PASSWORD
```

Use `Wizard` to administer the world. Codex connects as `LabProgrammer`.

## Manage the background service

The service starts at login and restarts the MOO after a failure, subject to systemd's retry limit. A deliberate stop does not trigger a restart. Use these commands to view logs or restart it:

```sh
journalctl --user -u toaststunt-llm-lab.service -f
systemctl --user restart toaststunt-llm-lab.service
```

Press Ctrl+C to stop following the logs; this does not stop the MOO. To stop the lab until you start it again or log in again:

```sh
systemctl --user stop toaststunt-llm-lab.service
```

When you are done testing, stop the lab and disable automatic startup at login:

```sh
./disable-service.sh
```

This keeps the installed service, world, credentials, and Codex registration. The service stays stopped until explicitly started. If you manually start it again, its `Restart=on-failure` policy applies while it is running.

To restore startup at login and start the installed service now:

```sh
systemctl --user enable --now toaststunt-llm-lab.service
```

Rerunning `./setup.sh` also enables and restarts the service. `./update-toaststunt.sh` starts or restarts it without changing whether it is enabled at login. Avoid these commands when you want the lab to stay stopped.

For startup at boot before login, you may need to enable lingering with `loginctl enable-linger "$USER"`. This setting affects all of your user services, not just the lab.

## Run manually or choose a specific database

To run the installed world in a terminal without systemd or automatic restarts:

```sh
./disable-service.sh
./restart.sh
```

Despite its name, `restart.sh` runs the engine once. It loads `state/toastcore.db`, first promoting `state/toastcore.db.new` if a completed checkpoint exists. Press Ctrl+C to stop and let the engine save.

To start from a specific database in `state/`, run the engine directly instead. Replace `state/my-world.db` with an existing, consistent database file and choose a separate filename for checkpoint output:

```sh
./disable-service.sh
flock -n state/server.lock ./state/engine -O --no-ipv6 -4 127.0.0.1 \
  state/my-world.db state/my-world.db.new "$(cat state/port)"
```

This uses the installed engine and saved port. The lock prevents another lab process using the same lock from running at the same time. The engine reads `state/my-world.db` and writes checkpoints to `state/my-world.db.new`. Press Ctrl+C to stop and let it save.

Direct engine commands do not automatically load an existing checkpoint. To resume from the checkpoint created above, use that file as input and a different file as output:

```sh
flock -n state/server.lock ./state/engine -O --no-ipv6 -4 127.0.0.1 \
  state/my-world.db.new state/my-world.resumed.db.new "$(cat state/port)"
```

On subsequent runs, use the most recent completed checkpoint as input. Never use the same file for input and output, and keep any existing output checkpoint you still need before reusing its filename. `./restart.sh` and the systemd service manage only the `state/toastcore.db` files; they do not resume these custom filenames. A different world needs its own accounts and MCP feature setup as described below.

## Run a second lab on the same host

Use a separate, fresh checkout with a distinct instance name and port:

```sh
TOASTSTUNT_LAB_INSTANCE=test MOO_PORT=7789 ./setup.sh --register-codex
```

This installs `toaststunt-llm-lab-test.service` and registers `toaststunt_llm_lab_test`. The checkout remembers its instance name and port. Instance names must contain lowercase letters or digits separated by hyphens; hyphens become underscores in the Codex name.

Use the instance's unit name in `systemctl` and `journalctl` commands. The setup, update, and disable scripts read the saved instance name automatically. Two checkouts cannot share the same service name.

## Checkpoints, backups, and alternate databases

For the installed world, the engine reads `state/toastcore.db` and publishes completed saves as `state/toastcore.db.new`. At the next startup, `restart.sh` copies the prior boot database to `state/toastcore.db.old`, then promotes the completed `.new` checkpoint to `state/toastcore.db`. The `.old` file is the previous boot database, which may be older than the previous checkpoint.

A clean systemd stop gives the engine up to 90 seconds to save. After a crash, the next startup loads the last completed checkpoint if one exists. For a backup, stop the lab and archive the entire `state/` directory, keeping the credentials with the world. Stop any manually launched engine too. Restoring on another machine also requires the engine and dependencies; `state/engine` normally points into this checkout's `vendor/` directory.

To create a fresh lab from an existing ToastStunt database, supply a consistent checkpoint as the seed:

```sh
MOO_PORT=7788 MOO_SEED_DB=/absolute/path/to/other-world.db ./setup.sh --server-only
```

This copies the seed to `state/toastcore.db` and starts the service. It does not change the world's passwords, create `LabProgrammer`, install the MOO feature, or register Codex. Follow the manual feature installation below. `--server-only` cannot be combined with `--register-codex`.

Prefer a separate checkout for each world. To replace a world in an existing checkout, stop the lab and move the entire `state/` directory to a private backup location outside the repository before running the alternate seed command. For a named instance, supply its original `TOASTSTUNT_LAB_INSTANCE` again, along with the desired `MOO_PORT`, because those settings were stored in the archived directory. Never mix one world's `.db.new` file or credentials with another world's database.

## Install the MOO feature manually

Automatic account and feature setup is intended for a fresh stock ToastCore world. For an existing database, create or select a programmer who is in a valid room and whose password you control. A non-wizard programmer is the default choice. Log in with wizard permissions to install the feature for that account.

The [stock ToastCore install transcript](moo/install.moo) contains the feature creation command, verb metadata, interactive `@program` commands, source, and attachment step. Replace `{{PROGRAMMER}}` with the target account's object number, such as `#123`. Run the first command, then replace `{{FEATURE}}` with the feature object number it returns. Run the remaining commands in order, allowing each `@program` session to finish before sending the next command.

Alternatively, install over the loopback connection from a Bash terminal:

```bash
read -rs -p 'Wizard password: ' MOO_PASSWORD; echo
export MOO_PASSWORD
python3 moo/install.py --port 7788 --username Wizard --programmer '#123'
unset MOO_PASSWORD
python3 configure-mcp.py
python3 verify-mcp.py
codex mcp add toaststunt_llm_lab -- python3 "$PWD/launch-mcp.py"
```

Replace the port, wizard login name, and programmer object with your world's values. `configure-mcp.py` prompts for the programmer's login name and password and stores them in `state/credentials.json`. For a named instance, use its Codex name in the final command. If you do not use the Codex CLI, add the generated `config.toml` entry to your client after verification.

After installing the feature, save a checkpoint from the wizard's MOO session with `;;dump_database();` and wait for the save to finish. The manual installer does not request a checkpoint for you. Continue using `./setup.sh --server-only` for later setup runs on this checkout; plain `./setup.sh` refuses automatic account setup on a world created with `--server-only`, even after a manual feature installation.

The MCP connection uses the programmer's authority. The feature's optional structured eval operation is disabled by default; the MCP server also exposes command and eval tools that use the account's normal MOO privileges. Disabling the feature's eval operation does not make the connection read-only.

To regenerate the interactive transcript from the canonical [feature source](moo/feature.moo):

```sh
python3 moo/install.py --transcript > moo/install.moo
```

## Update components or test a different MCP server

Rerun `./setup.sh` to fetch all three repositories' latest default-branch commits, rebuild the engine, refresh MCP dependencies when the MCP revision changes, and enable and restart the service. Use `./setup.sh --server-only` for a checkout created in server-only mode. Add `--register-codex` to a normal setup run only if you also want to add or update the Codex registration.

Existing world data and accounts are preserved. A successful automatic installation reuses its saved credentials on later runs; it does not generate new passwords each time. Updating ToastCore changes the seed available for a fresh world, not the database already running in `state/`. Setup refuses tracked source edits in vendor checkouts; commit or set aside your edits before updating. Untracked files are not included in that check.

To update only ToastStunt, or select a particular engine version:

```sh
./update-toaststunt.sh          # Fetch and build origin/master
./update-toaststunt.sh v2.8.0   # Or select an upstream tag or commit
```

Each engine revision builds in its own directory. The engine link changes only after a successful build, then the service restarts and loads the latest checkpoint. A later setup run selects the latest engine again. Before changing engine versions, stop the lab and keep a separate database backup: an older engine may be unable to load a checkpoint saved by a newer engine.

The MCP launcher runs `vendor/moo-mcp/src/index.js` with the lab profile at `vendor/moo-mcp/config/toaststunt-llm-lab.tools.json`. To use another MCP server repository, set `MOO_MCP_SOURCE` to a repository URL or an absolute checkout path when running setup. By default, setup fetches that source's default branch. To select a specific commit, also set `MOO_MCP_REVISION` to its full 40-character lowercase commit SHA. The selected commit must include the lab profile. Repeat these overrides on later setup runs if you want to keep using that source or commit.

## Uninstall

Run this from the checkout before moving or deleting it:

```sh
./disable-service.sh --remove
codex mcp remove toaststunt_llm_lab
```

The script stops and disables the user service, removes its installed unit file, and reloads systemd. It detects the saved instance name and refuses to change a service belonging to another checkout. It keeps the repository, `vendor/`, and all of `state/`, including the world and credentials. If you launched an engine manually, stop that process separately before removing files.

The Codex command removes the lab registration; skip it if you never registered the lab. For instance `test`, use `codex mcp remove toaststunt_llm_lab_test`. If you configured another client manually, remove its lab entry too. Start a fresh Codex chat after removing the registration.

Archive the entire `state/` directory if you want to keep the world and its credentials, then delete the checkout to remove the remaining local files. No system-wide packages are removed. Lingering is a user-wide setting, so the script leaves it alone. If you enabled it only for this lab and no longer need user services running while logged out, undo it with `loginctl disable-linger "$USER"`.

## Troubleshooting

- **Wizard login fails:** Read `wizard_password` from this checkout's `state/credentials.json` and use `connect Wizard PASSWORD`. Check that your client is connected to the port in `state/port`. A server-only world keeps its original accounts and passwords.
- **MCP verification fails:** Confirm the MOO is running, check the service logs, and verify the programmer credentials and installed feature. Registering the server in Codex does not start the MOO; the MOO must already be running.
- **The service stops retrying:** Inspect `journalctl --user -u toaststunt-llm-lab.service`. After fixing the cause, run `systemctl --user reset-failed toaststunt-llm-lab.service`, then start the service again. Substitute the instance's unit name when applicable.
- **The lab is locked:** Another setup, update, disable, or engine process may be running. Let it finish or stop it before retrying. Deleting a lock file does not safely release an active lock.
- **A boot database or credentials file is missing:** Restore the matching files from a backup. Do not delete the remaining checkpoints or credentials to force a fresh setup.

## Manual runtime layout on other operating systems

The automated setup requires Linux with systemd and GNU command-line utilities. On other systems, follow the [ToastStunt build instructions](https://github.com/lisdude/toaststunt#build-instructions), install the MCP server's npm dependencies, and provide the runtime layout below. The Linux `restart.sh` wrapper also uses GNU utilities; use equivalent checkpoint handling for your platform.

| Path | Contents |
| --- | --- |
| `state/engine` | Executable or symlink to your ToastStunt `moo` binary |
| `state/toastcore.db` | The starting database for this world |
| `state/toastcore.db.new` | Completed checkpoint output |
| `state/port` | One line containing the chosen local port |
| `state/node` | One line containing the absolute path to the Node executable |
| `state/credentials.json` | Programmer login for the MCP launcher; automatic stock setup also stores the Wizard password |
| `vendor/moo-mcp/` | MCP server checkout, including the lab profile, with dependencies installed using `npm ci` |

Keep `state/` private to your user and the credentials readable only by you. Before each launch, preserve the prior boot database and promote any completed checkpoint. Run the engine in the foreground with separate input and checkpoint output files, for example:

```sh
./state/engine -O --no-ipv6 -4 127.0.0.1 state/toastcore.db state/toastcore.db.new 7778
```

Then install the feature and configure the MCP login using the manual steps above. Create the client entry using `config.toml.example`, replacing its launcher path with your checkout's absolute path. `settings.sh.example` is a collection of command examples, not a configuration file read by setup. Generated configuration, credentials, vendor checkouts, databases, and logs are ignored by Git.
