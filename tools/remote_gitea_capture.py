"""Safe, deterministic remote Gitea capture and declaration conversion.

The module deliberately keeps transport and observation separate.  Remote
values are data only: they are validated, normalized, and never evaluated as
shell, Nix, or Python source.
"""

from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.request
import urllib.error
from dataclasses import dataclass
from typing import Any, Mapping, Sequence


SCHEMA = "osmium.remote-gitea-capture"
SCHEMA_VERSION = 1
ADAPTER = "nixos-gitea"
ADAPTER_VERSION = 1
MAX_OUTPUT = 4 * 1024 * 1024
SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]+$")
SAFE_PATH = re.compile(r"^/(?:var/lib/gitea|etc/gitea|run/gitea)(?:/.*)?$")
SENSITIVE = re.compile(
    r"(?:password|passwd|secret|token|api[_-]?key|private[_-]?key|hash|credential)", re.I
)


class CaptureError(RuntimeError):
    """An operational or artifact validation error."""


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _clean(value: Any, path: str = "") -> Any:
    """Drop sensitive fields recursively and normalize JSON-compatible data."""
    if isinstance(value, Mapping):
        result = {}
        for key in sorted(value):
            if SENSITIVE.search(str(key)):
                result[key] = {"present": bool(value[key]), "redacted": True}
            else:
                result[key] = _clean(value[key], f"{path}.{key}")
        return result
    if isinstance(value, list):
        return [_clean(item, path) for item in value]
    if isinstance(value, str):
        return value.replace("\x00", "")
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    raise CaptureError(f"unsupported value at {path or 'document'}")


def _sort_records(records: Sequence[Mapping[str, Any]], key: str) -> list[dict[str, Any]]:
    return [dict(item) for item in sorted(records, key=lambda item: (str(item.get(key, "")).casefold(), canonical_json(item)))]


def validate_path(value: str) -> str:
    if not isinstance(value, str) or not SAFE_PATH.fullmatch(value):
        raise CaptureError(f"path is outside the supported allowlist: {value!r}")
    return value


def normalize_capture(document: Mapping[str, Any]) -> dict[str, Any]:
    """Validate and canonicalize a capture supplied by a probe or fixture."""
    if document.get("schema") != SCHEMA or document.get("version") != SCHEMA_VERSION:
        raise CaptureError("unsupported capture schema or version")
    result = _clean(dict(document))
    required = ("adapter", "source", "scope", "service", "users", "organizations", "probes", "findings", "complete")
    missing = [key for key in required if key not in result]
    if missing:
        raise CaptureError("capture is missing: " + ", ".join(missing))
    if result["adapter"].get("name") != ADAPTER:
        raise CaptureError("unsupported adapter")
    result["users"] = _sort_records(result["users"], "username")
    result["organizations"] = _sort_records(result["organizations"], "name")
    result["persistence"] = sorted(result.get("persistence", []), key=canonical_json)
    for item in result["persistence"]:
        if isinstance(item, Mapping) and "path" in item:
            validate_path(item["path"])
    result["probes"] = _sort_records(result["probes"], "name")
    result["findings"] = sorted(result.get("findings", []), key=lambda item: (str(item.get("code", "")), canonical_json(item)))
    result["complete"] = bool(result["complete"]) and not any(
        finding.get("severity") in {"error", "required"} for finding in result["findings"]
    )
    result.pop("captured_at", None)
    return result


def validate_capture(document: Mapping[str, Any]) -> None:
    normalize_capture(document)


def render_capture(document: Mapping[str, Any]) -> str:
    return canonical_json(normalize_capture(document)) + "\n"


def _finding(code: str, severity: str, **fields: Any) -> dict[str, Any]:
    return {"code": code, "severity": severity, **fields}


def convert_capture(document: Mapping[str, Any], secret_files: Mapping[str, str] | None = None) -> dict[str, Any]:
    """Render a reviewed capture into the existing services.osmium.gitea shape."""
    capture = normalize_capture(document)
    secret_files = dict(secret_files or {})
    users: dict[str, dict[str, Any]] = {}
    organizations: dict[str, dict[str, Any]] = {}
    findings = list(capture["findings"])

    for user in capture["users"]:
        username = str(user.get("username", ""))
        if not username or not SAFE_NAME.fullmatch(username):
            findings.append(_finding("unsafe-name", "error", resource="user", username=username))
            continue
        if user.get("admin") or user.get("is_admin"):
            findings.append(_finding("administrator-account", "required", resource="user", username=username))
            continue
        if user.get("external_identity") or user.get("source") not in (None, "", "local", "internal"):
            findings.append(_finding("external-identity", "required", resource="user", username=username))
            continue
        key = "user_" + re.sub(r"[^a-z0-9]+", "_", username.casefold()).strip("_")
        if key in users:
            findings.append(_finding("duplicate-declaration-key", "error", resource="user", username=username))
            continue
        entry = {
            "username": username,
            "email": str(user.get("email", "")),
            "passwordFile": secret_files.get(username),
        }
        if not entry["passwordFile"]:
            findings.append(_finding("unresolved-secret-file", "required", resource="user", username=username))
        users[key] = entry

    for org in capture["organizations"]:
        name = str(org.get("name", ""))
        owner = str(org.get("owner", ""))
        if not name or not SAFE_NAME.fullmatch(name):
            findings.append(_finding("unsafe-name", "error", resource="organization", name=name))
            continue
        owner_key = "user_" + re.sub(r"[^a-z0-9]+", "_", owner.casefold()).strip("_")
        if not owner or owner_key not in users:
            findings.append(_finding("ambiguous-owner", "required", resource="organization", name=name, owner=owner))
            continue
        key = "organization_" + re.sub(r"[^a-z0-9]+", "_", name.casefold()).strip("_")
        organizations[key] = {
            "name": name,
            "owner": owner,
            "description": str(org.get("description", "")),
            "visibility": str(org.get("visibility", "private")),
        }

    for item in capture.get("unsupported", []):
        findings.append(_finding("unsupported-state", "required", resource=item))
    findings = sorted(findings, key=lambda item: (item.get("code", ""), canonical_json(item)))
    complete = bool(capture["complete"]) and not any(item["severity"] in {"error", "required"} for item in findings)
    return {
        "schema": "osmium.remote-gitea-candidate",
        "version": 1,
        "complete": complete,
        "activation_ready": complete,
        "source": {"schema": SCHEMA, "adapter": capture["adapter"]},
        "gitea": {
            "settings": capture.get("service", {}).get("settings", {}),
            "stateDir": capture.get("service", {}).get("stateDir", "/var/lib/gitea"),
            "persistence": capture.get("persistence", []),
            "users": dict(sorted(users.items())),
            "organizations": dict(sorted(organizations.items())),
        },
        "findings": findings,
    }


def render_nix(candidate: Mapping[str, Any]) -> str:
    """Render only safe scalar candidate fields as reviewable Nix-shaped text."""
    def nix(value: Any) -> str:
        if value is None:
            return "null"
        if isinstance(value, bool):
            return "true" if value else "false"
        if isinstance(value, str):
            return json.dumps(value)
        if isinstance(value, Mapping):
            return "{ " + " ".join(f"{key} = {nix(value[key])};" for key in sorted(value)) + " }"
        if isinstance(value, list):
            return "[ " + " ".join(nix(item) for item in value) + " ]"
        return str(value)

    gitea = candidate["gitea"]
    lines = ["# Generated by osmium-gitea-remote-convert; review before activation.", f"# complete = {str(candidate['complete']).lower()}", "services.osmium.gitea = {", f"  stateDir = {nix(gitea['stateDir'])};", "  users = {"]
    for key, user in sorted(gitea["users"].items()):
        password = "builtins.throw \"Supply a reviewed passwordFile\"" if not user["passwordFile"] else nix(user["passwordFile"])
        lines.append(f"    {key} = {{ username = {nix(user['username'])}; email = {nix(user['email'])}; passwordFile = {password}; }};")
    lines += ["  };", "  organizations = {"]
    for key, org in sorted(gitea["organizations"].items()):
        lines.append(f"    {key} = {{ name = {nix(org['name'])}; owner = {nix(org['owner'])}; description = {nix(org['description'])}; visibility = {nix(org['visibility'])}; }};")
    lines += ["  };", "};", ""]
    return "\n".join(lines)


@dataclass
class SSHTransport:
    host: str
    user: str
    port: int = 22
    identity_file: str | None = None
    known_hosts: str | None = None
    timeout: int = 15
    command: str = "ssh"

    def run(self, probe: str, payload: Mapping[str, Any] | None = None) -> dict[str, Any]:
        if probe not in ALLOWED_PROBES:
            raise CaptureError(f"probe is not allowlisted: {probe}")
        args = [self.command, "-o", "BatchMode=yes", "-o", f"ConnectTimeout={self.timeout}", "-o", "StrictHostKeyChecking=yes"]
        if self.known_hosts:
            args += ["-o", f"UserKnownHostsFile={self.known_hosts}"]
        if self.identity_file:
            args += ["-i", self.identity_file]
        args += ["-p", str(self.port), f"{self.user}@{self.host}", "osmium-gitea-probe", probe]
        try:
            completed = subprocess.run(args, input=(canonical_json(payload or {}) + "\n").encode(), capture_output=True, timeout=self.timeout + 5, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise CaptureError(f"ssh transport failed during {probe}") from error
        if completed.returncode:
            raise CaptureError(f"remote probe failed during {probe} (status {completed.returncode})")
        if len(completed.stdout) > MAX_OUTPUT:
            raise CaptureError(f"remote probe exceeded output limit during {probe}")
        try:
            value = json.loads(completed.stdout)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise CaptureError(f"remote probe returned invalid JSON during {probe}") from error
        if not isinstance(value, dict):
            raise CaptureError(f"remote probe returned a non-object during {probe}")
        return value


ALLOWED_PROBES = frozenset({"platform", "service", "identities", "persistence"})


def local_probe(name: str) -> dict[str, Any]:
    """Answer the fixed probe vocabulary on a NixOS Gitea host."""
    if name not in ALLOWED_PROBES:
        raise CaptureError(f"probe is not allowlisted: {name}")
    if name == "platform":
        facts = {}
        try:
            for line in open("/etc/os-release", encoding="utf-8"):
                if "=" in line:
                    key, value = line.rstrip().split("=", 1)
                    facts[key] = value.strip('"')
        except OSError as error:
            raise CaptureError("platform probe failed") from error
        return {"status": "ok", "platform": "nixos" if facts.get("ID") == "nixos" else facts.get("ID", "unknown")}
    if name == "persistence":
        return {"status": "ok", "paths": [{"path": "/var/lib/gitea", "origin": "observed"}]}
    if name == "identities":
        token_file = os.environ.get("OSMIUM_GITEA_API_TOKEN_FILE")
        if not token_file:
            return {"status": "unsupported", "findings": [_finding("identity-observation-unavailable", "required")], "users": [], "organizations": []}
        try:
            token = open(token_file, encoding="utf-8").read().strip()
            if not token:
                raise OSError("empty token")
            base = os.environ.get("OSMIUM_GITEA_API_URL", "http://127.0.0.1:3000/api/v1").rstrip("/")

            def pages(endpoint: str) -> list[dict[str, Any]]:
                records = []
                page = 1
                while True:
                    request = urllib.request.Request(f"{base}/{endpoint}?limit=50&page={page}", headers={"Authorization": f"token {token}"})
                    with urllib.request.urlopen(request, timeout=10) as response:
                        batch = json.load(response)
                    if not isinstance(batch, list):
                        raise ValueError("API returned a non-list")
                    records.extend(batch)
                    if len(batch) < 50:
                        return records
                    page += 1

            users = [{"username": item.get("login", ""), "email": item.get("email", ""), "admin": bool(item.get("is_admin", False)), "source": "local"} for item in pages("admin/users")]
            organizations = [{"name": item.get("username", ""), "description": item.get("description", ""), "visibility": item.get("visibility", ""), "owner": (item.get("owner") or {}).get("login", "")} for item in pages("admin/orgs")]
            return {"status": "ok", "users": users, "organizations": organizations}
        except (OSError, ValueError, urllib.error.URLError) as error:
            return {"status": "error", "findings": [_finding("identity-observation-failed", "error")], "error_class": type(error).__name__, "users": [], "organizations": []}

    settings: dict[str, dict[str, str]] = {}
    config_path = "/var/lib/gitea/custom/conf/app.ini"
    parser = configparser.ConfigParser(interpolation=None)
    try:
        parser.read(config_path, encoding="utf-8")
    except (OSError, configparser.Error) as error:
        return {"status": "unsupported", "findings": [_finding("service-config-unavailable", "required")], "error_class": type(error).__name__}
    for section in ("server", "service", "database"):
        if section in parser:
            settings[section] = {key: value for key, value in parser[section].items() if not SENSITIVE.search(key)}
    return {"status": "ok", "service": {"stateDir": "/var/lib/gitea", "settings": settings, "paths": [config_path, "/var/lib/gitea"]}}


def capture(transport: SSHTransport, scope: str = "gitea") -> dict[str, Any]:
    platform = transport.run("platform")
    if platform.get("platform") != "nixos":
        raise CaptureError("unsupported-host: remote platform is not NixOS")
    observations = {probe: transport.run(probe, {"scope": scope}) for probe in ("service", "identities", "persistence")}
    findings: list[dict[str, Any]] = []
    for name, value in observations.items():
        if value.get("status") == "unsupported":
            findings.append(_finding("unsupported-probe", "required", probe=name))
        elif value.get("status") != "ok":
            findings.append(_finding("probe-failed", "error", probe=name))
    service = observations["service"].get("service", {})
    for path in service.get("paths", []):
        validate_path(path)
    artifact = {
        "schema": SCHEMA,
        "version": SCHEMA_VERSION,
        "adapter": {"name": ADAPTER, "version": ADAPTER_VERSION, "probes": sorted(ALLOWED_PROBES)},
        "source": {"host": hashlib.sha256(transport.host.encode()).hexdigest()[:16], "origin": "observed"},
        "scope": scope,
        "service": service,
        "users": observations["identities"].get("users", []),
        "organizations": observations["identities"].get("organizations", []),
        "persistence": observations["persistence"].get("paths", []),
        "probes": [{"name": name, "status": value.get("status", "unknown"), "origin": "observed"} for name, value in observations.items()],
        "findings": findings,
        "complete": not findings,
    }
    return normalize_capture(artifact)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="osmium-gitea-remote")
    sub = parser.add_subparsers(dest="command", required=True)
    normalize = sub.add_parser("normalize")
    normalize.add_argument("input", nargs="?", default="-")
    convert = sub.add_parser("convert")
    convert.add_argument("input")
    convert.add_argument("--output")
    convert.add_argument("--secret-file", action="append", default=[], metavar="USERNAME=PATH")
    capture_parser = sub.add_parser("capture")
    capture_parser.add_argument("--host", required=True)
    capture_parser.add_argument("--user", required=True)
    capture_parser.add_argument("--port", type=int, default=22)
    capture_parser.add_argument("--identity-file")
    capture_parser.add_argument("--known-hosts", required=True)
    capture_parser.add_argument("--output")
    probe_parser = sub.add_parser("probe")
    probe_parser.add_argument("probe", choices=sorted(ALLOWED_PROBES))
    args = parser.parse_args(argv)

    try:
        if args.command == "probe":
            output = canonical_json(local_probe(args.probe)) + "\n"
        elif args.command == "capture":
            output = render_capture(capture(SSHTransport(args.host, args.user, args.port, args.identity_file, args.known_hosts, command=os.environ.get("OSMIUM_SSH_COMMAND", "ssh")), "gitea"))
        else:
            source = sys.stdin.read() if args.input == "-" else open(args.input, encoding="utf-8").read()
            document = json.loads(source)
            if args.command == "normalize":
                output = render_capture(document)
            else:
                secret_files = dict(item.split("=", 1) for item in args.secret_file if "=" in item)
                output = canonical_json(convert_capture(document, secret_files)) + "\n"
        if args.command == "convert" and args.output and args.output.endswith(".nix"):
            output = render_nix(json.loads(output))
        if getattr(args, "output", None):
            with open(args.output, "w", encoding="utf-8") as handle:
                handle.write(output)
        else:
            sys.stdout.write(output)
        return 0
    except (CaptureError, OSError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
