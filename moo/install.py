#!/usr/bin/env python3
"""Install or exercise the feature over a ToastStunt console connection."""

import argparse
import json
import os
import pathlib
import re
import socket
import time
import uuid

HERE = pathlib.Path(__file__).resolve().parent
BOOTSTRAP = "MOO-MCP-INSTALL "
RESPONSE = "MOO-MCP "


class Console:
    def __init__(self, host, port, username, password):
        if any(char in username + password for char in "\r\n\x00"):
            raise ValueError("Login credentials must fit on one console line")
        self.socket = socket.create_connection((host, port), timeout=5)
        self.socket.settimeout(0.25)
        self.command("connect " + username + (" " + password if password else ""))

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.socket.close()

    def send(self, line):
        self.socket.sendall((line + "\r\n").encode())

    def command(self, line, timeout=12, until=None):
        self.send(line)
        deadline = time.monotonic() + timeout
        parts = []
        while time.monotonic() < deadline:
            try:
                chunk = self.socket.recv(65536)
            except TimeoutError:
                if parts and until is None:
                    return "".join(parts)
                continue
            if not chunk:
                raise ConnectionError("MOO disconnected")
            parts.append(chunk.decode(errors="replace"))
            output = "".join(parts)
            if until and any(until(row) for row in output.split("\n")[:-1]):
                return output
        raise TimeoutError("MOO did not complete the request. " + "".join(parts)[-500:])

    def message(self, command, prefix, request_id=None, timeout=15):
        def decode(line):
            if line.startswith(prefix):
                try:
                    return json.loads(line[len(prefix):])
                except json.JSONDecodeError:
                    return None
            return None

        def matches(line):
            value = decode(line)
            return value is not None and (
                request_id is None or value.get("id") == request_id
            )

        output = self.command(command, timeout=timeout, until=matches)
        return next(decode(line) for line in output.splitlines() if matches(line))

    def evaluate(self, body):
        caught = (
            f'try {body} except error (ANY) '
            f'notify(player, "{BOOTSTRAP}" + generate_json(["install_error" -> error[2]])); endtry'
        )
        result = self.message(";;" + caught, BOOTSTRAP)
        if isinstance(result, dict) and "install_error" in result:
            raise RuntimeError(result["install_error"])
        return result

    def request(self, operation, parameters):
        request_id = uuid.uuid4().hex
        payload = json.dumps(
            {"id": request_id, "op": operation, "params": parameters},
            ensure_ascii=True, separators=(",", ":"),
        )
        return self.message("@mcp " + payload, RESPONSE, request_id)


def definitions():
    for section in (HERE / "feature.moo").read_text().strip().split("\n@@ "):
        metadata, body = section.removeprefix("@@ ").split("\n", 1)
        name, *args = metadata.split()
        yield name, args, body.rstrip()


def feature_setup(programmer, allow_eval, feature_parent):
    if programmer is not None and not re.fullmatch(r"#[0-9]+", programmer):
        raise ValueError("Programmer must be a numbered MOO object")
    if not re.fullmatch(r"(?:#[0-9]+|\$[A-Za-z_][A-Za-z_0-9]*)", feature_parent):
        raise ValueError("Feature parent must be a numbered object or a core reference")
    target = programmer or "player"
    enabled = "true" if allow_eval else "false"
    return f'''who = {target};
if (!valid(who) || !is_player(who) || !who.programmer || typeof(who.features) != LIST)
  raise(E_INVARG, "A programmer with feature support is required.");
endif
for f in (who.features)
  if (valid(f) && `f.mcp_programmer == who && f.name == "MOO MCP Feature" ! E_PROPNF, E_PERM => 0')
    raise(E_INVARG, "This programmer already has an MCP feature.");
  endif
endfor
f = create({feature_parent}, who);
f.name = "MOO MCP Feature";
set_verb = {{who, "r"}};
add_property(f, "mcp_programmer", who, set_verb);
add_property(f, "mcp_eval_enabled", {enabled}, set_verb);
add_property(f, "mcp_prototypes", [], set_verb);
f.feature_ok = 1;
notify(player, "{BOOTSTRAP}" + generate_json([ "object" -> tostr(f), "programmer" -> tostr(who)]));'''



def stub(obj, account, name, args):
    return (
        f'add_verb({obj}, {{{account}, "rxd", "{name}"}}, '
        '{' + ', '.join(json.dumps(arg) for arg in args) + '}); '
        f'notify(player, "{BOOTSTRAP}true");'
    )


def attach(obj, account):
    return (
        f'{obj}.feature_verbs = {{"@mcp"}}; '
        f'added = {account}:add_feature({obj}); '
        f'notify(player, "{BOOTSTRAP}" + generate_json(["attached" -> '
        f'({obj} in {account}.features) && added == 1, "object" -> tostr({obj}), '
        f'"programmer" -> tostr({account})]));'
    )


def one_line(body):
    return " ".join(body.splitlines())


def transcript():
    """Render the complete interactive install, with refs filled in by the operator."""
    setup = feature_setup(None, False, "$feature").replace("who = player;", "who = {{PROGRAMMER}};", 1)
    print(";;" + one_line(setup))
    print()
    for name, args, body in definitions():
        print(";;" + stub("{{FEATURE}}", "{{PROGRAMMER}}", name, args))
        print(f"@program {{{{FEATURE}}}}:{name}")
        print(body)
        print(".")
        print()
    print(";;" + attach("{{FEATURE}}", "{{PROGRAMMER}}"))


def install(connection, programmer=None, allow_eval=False, feature_parent="$feature"):
    receipt = connection.evaluate(one_line(feature_setup(programmer, allow_eval, feature_parent)))
    obj, account = receipt["object"], receipt["programmer"]
    if not all(re.fullmatch(r"#[0-9]+", ref) for ref in (obj, account)):
        raise RuntimeError("Invalid install receipt")
    print(f"Created feature {obj} for {account}", flush=True)
    try:
        names = []
        for name, args, body in definitions():
            names.append(name)
            connection.evaluate(stub(obj, account, name, args))
            prompt = connection.command(f"@program {obj}:{name}")
            if not re.search(r"programming|lines of input", prompt, re.I):
                raise RuntimeError(f"Unable to start @program for {name}: {prompt}")
            result = connection.command(body + "\n.")
            if "brief, single line note" in result:
                result += connection.command("Install the portable MCP feature.")
            if "submit diff" in result.lower():
                result += connection.command("no")
            check = connection.evaluate(
                f'code = verb_code({obj}, "{name}", false, true); '
                f'metadata = verb_info({obj}, "{name}"); '
                f'notify(player, "{BOOTSTRAP}" + generate_json('
                f'["code" -> code, "metadata" -> {{tostr(metadata[1]), metadata[2], metadata[3]}}, '
                f'"args" -> verb_args({obj}, "{name}")], "common-subset", true));'
            )
            code = [line for line in check["code"] if not line.startswith(
                ('"VMS NOTE ', '"VMS VERSION ', '"Last modified by '))]
            expected = [line for line in body.splitlines() if line.strip()]
            if (len(code) != len(expected) or code[0] != expected[0]
                    or check["metadata"] != [account, "rxd", name] or check["args"] != args):
                raise RuntimeError(f"Unexpected source or metadata after programming {name}: {result}")
        receipt = connection.evaluate(attach(obj, account))
        if not receipt["attached"]:
            raise RuntimeError("Core rejected feature attachment")
        receipt["verbs"] = names
        return receipt
    except Exception as err:
        raise RuntimeError(f"Install incomplete on {obj}. The feature package should be inspected before retrying. {err}") from err


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int)
    parser.add_argument("--username")
    parser.add_argument("--programmer", help="Install for an existing programmer when logged in as wizard")
    parser.add_argument("--feature-parent", default="$feature")
    parser.add_argument("--allow-eval", action="store_true")
    parser.add_argument("--request", nargs=2, metavar=("OP", "PARAMS_JSON"))
    parser.add_argument("--transcript", action="store_true", help="Print the manual stock ToastCore install")
    args = parser.parse_args()
    if args.transcript:
        transcript()
        return
    if not args.port or not args.username:
        parser.error("--port and --username are required for a live connection")
    with Console(args.host, args.port, args.username, os.environ.get("MOO_PASSWORD", "")) as connection:
        if args.request:
            result = connection.request(args.request[0], json.loads(args.request[1]))
        else:
            result = install(connection, args.programmer, args.allow_eval, args.feature_parent)
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
