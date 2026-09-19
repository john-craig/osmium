#!/usr/bin/env python3
import base64
import json
import os
import pty
import select
import signal
import sys
import time
import urllib.request


BASE_URL = os.environ.get("OPENCODE_BASE_URL", "http://127.0.0.1:4096")
USERNAME = os.environ.get("OPENCODE_SERVER_USERNAME", "opencode")
PASSWORD = os.environ["OPENCODE_SERVER_PASSWORD"]
OPENCODE_BIN = os.environ.get("OPENCODE_BIN", "opencode")
MARKER = os.environ.get("OPENCODE_ATTACH_MARKER", "terminal-attach-marker")
OUTPUT = os.environ.get("OPENCODE_ATTACH_OUTPUT", "/tmp/opencode-attach-pty.log")


def request_json(path):
    credentials = base64.b64encode(f"{USERNAME}:{PASSWORD}".encode()).decode()
    request = urllib.request.Request(
        BASE_URL + path,
        headers={"Authorization": f"Basic {credentials}"},
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.load(response)


def find_session():
    sessions = request_json("/session")
    for session in sessions:
        session_id = session.get("id")
        if not session_id:
            continue
        messages = request_json(f"/session/{session_id}/message")
        if MARKER in json.dumps(messages):
            return session_id
    return None


pid, fd = pty.fork()
if pid == 0:
    os.environ.setdefault("OPENCODE_AUTO_SERVE", "false")
    os.execl(OPENCODE_BIN, OPENCODE_BIN, "attach", BASE_URL)

transcript = bytearray()
started = time.monotonic()
deadline = started + 30
submitted = False
while time.monotonic() < deadline:
    ready, _, _ = select.select([fd], [], [], 0.25)
    if ready:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        transcript.extend(chunk)
    if not submitted and time.monotonic() - started > 8:
        os.write(fd, (MARKER + "\r").encode())
        submitted = True
        time.sleep(5)
        os.write(fd, b"\x03")

try:
    os.kill(pid, signal.SIGTERM)
except ProcessLookupError:
    pass
_, status = os.waitpid(pid, 0)
with open(OUTPUT, "wb") as output:
    output.write(transcript)

session_id = None
for _ in range(10):
    try:
        session_id = find_session()
    except Exception:
        pass
    if session_id:
        break
    time.sleep(0.5)

if not session_id:
    print("attach session containing marker was not found", file=sys.stderr)
    print(transcript.decode(errors="replace"), file=sys.stderr)
    sys.exit(1)

with open(OUTPUT + ".session", "w", encoding="utf-8") as output:
    output.write(session_id + "\n")
print(session_id)
