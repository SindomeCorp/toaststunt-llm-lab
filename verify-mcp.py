#!/usr/bin/env python3
"""Check an actual stdio MCP handshake and tool call using the local launcher."""

import json
from pathlib import Path
import selectors
import subprocess
import sys


def main():
    launcher = Path(__file__).with_name("launch-mcp.py")
    with subprocess.Popen(
        [sys.executable, str(launcher)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
    ) as child, selectors.DefaultSelector() as ready:
        ready.register(child.stdout, selectors.EVENT_READ)

        def send(method, params, request_id=None):
            packet = {"jsonrpc": "2.0", "method": method, "params": params}
            if request_id is not None:
                packet["id"] = request_id
            child.stdin.write(json.dumps(packet) + "\n")
            child.stdin.flush()
            if request_id is None:
                return None
            if not ready.select(timeout=20):
                raise TimeoutError(f"No MCP reply for {method}")
            reply = json.loads(child.stdout.readline())
            if reply.get("id") != request_id or "result" not in reply:
                raise RuntimeError(f"Unexpected MCP reply: {reply}")
            return reply["result"]

        try:
            send("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                "clientInfo": {"name": "lab-verifier", "version": "1"}}, 1)
            send("notifications/initialized", {})
            tools = send("tools/list", {}, 2)["tools"]
            names = {tool["name"] for tool in tools}
            expected = {"run_moo_command", "run_moo_eval", "hello", "verb-data", "search-json"}
            if not expected <= names or {"bugs-json", "next-unreviewed-traceback-json"} & names:
                raise RuntimeError("Unexpected tool catalog for the ToastStunt lab profile.")

            def tool(name, arguments, request_id):
                result = send("tools/call", {"name": name, "arguments": arguments}, request_id)
                if result.get("isError"):
                    raise RuntimeError(f"Lab tool {name} failed.")
                return json.loads(result["content"][0]["text"])

            hello = tool("hello", {}, 3)
            if hello["protocol"] != 1:
                raise RuntimeError("Unexpected protocol from the lab feature.")
            source = tool("verb-data", {"object": hello["feature"], "verb": "@mcp"}, 4)
            if not source["source"]["code_lines"]:
                raise RuntimeError("The lab profile could not read the installed verb source.")
            print(f"MCP verified: {len(tools)} tools, feature {hello['feature']}.")
        finally:
            child.stdin.close()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


if __name__ == "__main__":
    main()
