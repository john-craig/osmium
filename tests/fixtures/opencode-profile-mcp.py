#!/usr/bin/env python3
import json
import os
import sys


name = sys.argv[1]
marker = sys.argv[2]
tool_name = f"{name}_lookup"
framed = False
wire_transcript = f"{marker}.wire"


def reply(request_id, result=None, error=None):
    response = {"jsonrpc": "2.0", "id": request_id}
    if error is not None:
        response["error"] = error
    else:
        response["result"] = result
    payload = json.dumps(response, sort_keys=True)
    with open(wire_transcript, "a", encoding="utf-8") as output:
        output.write(json.dumps({"direction": "response", "payload": response}, sort_keys=True) + "\n")
    if framed:
        sys.stdout.write(f"Content-Length: {len(payload.encode('utf-8'))}\r\n\r\n{payload}")
    else:
        sys.stdout.write(payload + "\n")
    sys.stdout.flush()


input_stream = sys.stdin.buffer
while True:
    line = input_stream.readline()
    if not line:
        break
    if line.lower().startswith(b"content-length:"):
        framed = True
        length = int(line.split(b":", 1)[1].strip())
        input_stream.readline()
        line = input_stream.read(length)
    try:
        request = json.loads(line)
    except json.JSONDecodeError:
        continue

    method = request.get("method")
    with open(wire_transcript, "a", encoding="utf-8") as output:
        output.write(json.dumps({"direction": "request", "payload": request}, sort_keys=True) + "\n")
    with open(f"{marker}.transcript", "a", encoding="utf-8") as output:
        output.write(method or "notification")
        output.write(" framed=" + str(framed) + "\n")
        if method == "tools/call":
            output.write(json.dumps(request, sort_keys=True) + "\n")
    request_id = request.get("id")
    if request_id is None:
        continue
    if method == "initialize":
        reply(
            request_id,
            {
                "protocolVersion": request.get("params", {}).get("protocolVersion", "2024-11-05"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": f"osmium-{name}", "version": "1"},
            },
        )
    elif method == "tools/list":
        reply(
            request_id,
            {
                "tools": [
                    {
                        "name": tool_name,
                        "description": f"Deterministic {name} profile fixture",
                        "inputSchema": {
                            "type": "object",
                            "properties": {"key": {"type": "string"}},
                            "required": ["key"],
                            "additionalProperties": False,
                        },
                    }
                ]
            },
        )
    elif method == "tools/call":
        params = request.get("params", {})
        arguments = params.get("arguments", {})
        if params.get("name") != tool_name or set(arguments) != {"key"} or not isinstance(arguments["key"], str):
            reply(request_id, error={"code": -32602, "message": "invalid fixture tool arguments"})
        elif os.environ.get("MCP_TOKEN", "").startswith("old-"):
            reply(request_id, error={"code": -32001, "message": "invalid fixture token"})
        else:
            with open(marker, "a", encoding="utf-8") as output:
                output.write(f"{name}:{arguments['key']}\n")
            reply(
                request_id,
                {
                    "content": [{"type": "text", "text": json.dumps({"fixture": name, "key": arguments["key"], "value": f"{name}-value"}, sort_keys=True)}],
                    "structuredContent": {"fixture": name, "key": arguments["key"], "value": f"{name}-value"},
                },
            )
