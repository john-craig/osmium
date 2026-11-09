#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import json


transcript = "/tmp/opencode-profile-provider-transcript.jsonl"
wire_transcript = "/tmp/opencode-profile-provider-wire.jsonl"
summary_transcript = "/tmp/opencode-profile-provider-summary.jsonl"


def stream(request, message):
    model = request.get("model", "mock")
    if "tool_calls" in message:
        chunks = [
            ({"role": "assistant", "tool_calls": [dict(call, index=index) for index, call in enumerate(message["tool_calls"])]}, None),
            ({}, "tool_calls"),
        ]
    else:
        chunks = [
            ({"role": "assistant", "content": message["content"]}, None),
            ({}, "stop"),
        ]
    body = "".join(
        "data: " + json.dumps({"id": "profile-completion", "object": "chat.completion.chunk", "created": 0, "model": model, "choices": [{"index": 0, "delta": chunk, "finish_reason": finish_reason}]}) + "\n\n"
        for chunk, finish_reason in chunks
    ) + "data: [DONE]\n\n"
    return body.encode()


def requested_tool(prompt, tools):
    marker = next((line for line in prompt.splitlines() if line.startswith("MCP_CALL ")), "")
    if not marker:
        return None
    requested = marker.split(" ", 1)[1].split(" ", 1)[0]
    return next((tool for tool in tools if tool.get("function", {}).get("name") == requested), None)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/v1/models":
            self.send_error(404)
            return
        body = json.dumps({"object": "list", "data": [{"id": "mock", "object": "model"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/v1/chat/completions" or self.headers.get("Authorization") != "Bearer provider-token":
            self.send_error(401)
            return
        request = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        messages = request.get("messages", [])
        tools = request.get("tools", [])
        with open(wire_transcript, "a", encoding="utf-8") as output:
            output.write(json.dumps({"stream": request.get("stream"), "messages": messages, "tools": tools}, sort_keys=True) + "\n")
        with open(summary_transcript, "a", encoding="utf-8") as output:
            output.write(json.dumps({
                "stream": request.get("stream"),
                "roles": [message.get("role") for message in messages],
                "system_has_facts_rule": "Selected profile: facts" in "\n".join(message.get("content", "") or "" for message in messages if message.get("role") == "system"),
                "system_has_audit_rule": "Selected profile: audit" in "\n".join(message.get("content", "") or "" for message in messages if message.get("role") == "system"),
                "tools": [tool.get("function", {}).get("name") for tool in tools],
                "tool_messages": [message.get("tool_call_id") for message in messages if message.get("role") == "tool"],
            }, sort_keys=True) + "\n")
        system = "\n".join(message.get("content", "") or "" for message in messages if message.get("role") == "system")
        tool_messages = [message for message in messages if message.get("role") == "tool"]
        with open(transcript, "a", encoding="utf-8") as output:
            output.write(json.dumps({"system": system, "tools": [tool.get("function", {}).get("name") for tool in tools], "tool_results": [message.get("content") for message in tool_messages], "response": "profile-mcp-ok" if tool_messages else "tool-call"}, sort_keys=True) + "\n")

        if tool_messages:
            message = {
                "content": "profile-mcp-ok"
                if any('"fixture":' in (item.get("content") or "") for item in tool_messages)
                else "mcp-result-ok"
            }
        else:
            prompt = next((message.get("content", "") for message in reversed(messages) if message.get("role") == "user"), "")
            selected = requested_tool(prompt, tools)
            profile_name = next(
                (name for name in ("facts", "audit", "ordinary", "osmium-support") if f"Selected profile: {name}" in system),
                "facts",
            )
            if "ordinary-profile-marker" in system:
                profile_name = "ordinary"
            if any(tool.get("function", {}).get("name", "").startswith("opencode-support_") for tool in tools):
                profile_name = "osmium-support"
            if selected:
                selected_name = selected.get("function", {}).get("name", "")
                profile_name = next(
                    (name for name in ("facts", "audit", "ordinary", "osmium-support") if selected_name.startswith({"facts": "facts_", "audit": "audit_", "ordinary": "ordinary_", "osmium-support": "opencode-support_"}[name])),
                    profile_name,
                )
            if profile_name in ("ordinary", "osmium-support") and not selected and not any(
                line.startswith("MCP_CALL ") for line in prompt.splitlines()
            ):
                message = {"content": "agent-dispatch-ok"}
                body = stream(request, message) if request.get("stream") else json.dumps({"id": "profile-completion", "object": "chat.completion", "created": 0, "model": request.get("model", "mock"), "choices": [{"index": 0, "message": {"role": "assistant", **message}, "finish_reason": "stop"}]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream" if request.get("stream") else "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            matching_tools = [selected] if selected else [tool for tool in tools if tool.get("function", {}).get("name", "").startswith(profile_name + "_")]
            if not matching_tools:
                self.send_error(400)
                return
            tool = matching_tools[0].get("function", {})
            arguments = {"key": "profile"}
            if "MCP_ARGS " in prompt:
                try:
                    arguments = json.loads(prompt.split("MCP_ARGS ", 1)[1].splitlines()[0])
                except json.JSONDecodeError:
                    self.send_error(400)
                    return
            message = {"tool_calls": [{"id": "profile-call", "type": "function", "function": {"name": tool["name"], "arguments": json.dumps(arguments)}}]}

        body = stream(request, message) if request.get("stream") else json.dumps({"id": "profile-completion", "object": "chat.completion", "created": 0, "model": request.get("model", "mock"), "choices": [{"index": 0, "message": {"role": "assistant", **message}, "finish_reason": "tool_calls" if "tool_calls" in message else "stop"}]}).encode()
        with open(wire_transcript, "a", encoding="utf-8") as output:
            output.write(json.dumps({"response": body.decode("utf-8")}, sort_keys=True) + "\n")
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream" if request.get("stream") else "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


HTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
