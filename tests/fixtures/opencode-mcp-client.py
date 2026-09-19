#!/usr/bin/env python3
"""Small deterministic MCP stdio client used by the OpenCode MicroVM checks."""

import argparse
import json
import os
import subprocess
import sys


def read_message(stream):
    first = stream.readline()
    if not first:
        raise RuntimeError("MCP server closed stdout")
    if first.lstrip().startswith(b"{"):
        return json.loads(first)
    headers = {}
    line = first
    while True:
        if line in (b"\r\n", b"\n"):
            break
        key, value = line.decode().split(":", 1)
        headers[key.lower()] = value.strip()
        line = stream.readline()
        if not line:
            raise RuntimeError("MCP server closed stdout")
    length = int(headers["content-length"])
    return json.loads(stream.read(length))


def write_message(stream, payload):
    stream.write(json.dumps(payload, separators=(",", ":")).encode() + b"\n")
    stream.flush()


def request(process, request_id, method, params=None):
    write_message(process.stdin, {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params or {}})
    while True:
        response = read_message(process.stdout)
        if response.get("id") == request_id:
            if "error" in response:
                raise RuntimeError(json.dumps(response["error"], sort_keys=True))
            return response["result"]


def call(process, request_id, name, arguments):
    return request(process, request_id, "tools/call", {"name": name, "arguments": arguments})


parser = argparse.ArgumentParser()
parser.add_argument("executable")
parser.add_argument("--output", required=True)
parser.add_argument("--call", action="append", default=[])
args = parser.parse_args()

environment = os.environ.copy()
environment["OPENCODE_AUTO_SERVE"] = "false"
process = subprocess.Popen([args.executable], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
try:
    initialize = request(process, 1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "osmium-test", "version": "1"}})
    write_message(process.stdin, {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
    tools = request(process, 2, "tools/list")
    calls = []
    next_id = 3
    for encoded in args.call:
        name, raw_arguments = encoded.split("=", 1)
        result = call(process, next_id, name, json.loads(raw_arguments))
        calls.append({"name": name, "result": result})
        next_id += 1
    with open(args.output, "w", encoding="utf-8") as output:
        json.dump({"initialize": initialize, "tools": tools, "calls": calls}, output, sort_keys=True)
        output.write("\n")
except Exception as error:
    process.terminate()
    process.wait(timeout=5)
    stderr = process.stderr.read().decode("utf-8", errors="replace").strip()
    detail = f"; stderr={stderr}" if stderr else ""
    raise RuntimeError(f"{error}{detail}") from error
finally:
    process.terminate()
    process.wait(timeout=5)
