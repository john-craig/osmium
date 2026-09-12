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
REPOSITORY_FIELDS = ("description", "private", "default_branch", "website", "issues", "wiki", "pull_requests")
REPOSITORY_API_FIELDS = {
    "has_issues": "issues",
    "has_wiki": "wiki",
    "has_pull_requests": "pull_requests",
}


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


def _repository_key(repository: Mapping[str, Any]) -> tuple[str, str, str]:
    return (str(repository.get("owner_kind", "")).casefold(), str(repository.get("owner", "")).casefold(), str(repository.get("name", "")).casefold())


def _normalize_repository(value: Mapping[str, Any]) -> dict[str, Any]:
    owner = value.get("owner")
    if isinstance(owner, Mapping):
        owner_kind = "user" if owner.get("user") else "organization" if owner.get("organization") else ""
        owner = owner.get("login") or owner.get("username") or owner.get("name") or owner.get("user") or owner.get("organization")
    else:
        owner_kind = ""
    record: dict[str, Any] = {
        "owner_kind": str(value.get("owner_kind") or value.get("owner_type") or value.get("kind") or value.get("ownerType") or owner_kind).casefold(),
        "owner": str(owner or ""),
        "name": str(value.get("name") or value.get("repo") or ""),
    }
    for field in REPOSITORY_FIELDS:
        api_field = next((key for key, normalized in REPOSITORY_API_FIELDS.items() if normalized == field), field)
        if field in value:
            record[field] = value[field]
        elif api_field in value:
            record[field] = value[api_field]
    record["unsupported"] = sorted(str(item) for item in value.get("unsupported", []))
    if value.get("content_required") or value.get("contents") or value.get("git_objects"):
        record["unsupported"].append("repository-content")
    if any(key in value for key in ("webhooks", "deploy_keys", "hooks", "collaborators")):
        record["unsupported"].append("sensitive-or-unmanaged-integrations")
    record["unsupported"] = sorted(set(record["unsupported"]))
    if "provenance" in value:
        record["provenance"] = _clean(value["provenance"])
    return record


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
    result["repositories"] = sorted(
        (_normalize_repository(item) for item in result.get("repositories", [])),
        key=lambda item: (_repository_key(item), canonical_json(item)),
    )
    for repository in result["repositories"]:
        if not repository["owner_kind"] or not repository["owner"] or not repository["name"]:
            result["findings"].append(_finding("repository-required-field-missing", "required", repository=repository))
        if repository["owner_kind"] not in {"user", "organization"}:
            result["findings"].append(_finding("ambiguous-owner", "required", repository=repository))
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
    repositories: dict[str, dict[str, Any]] = {}
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
    for repository in capture.get("repositories", []):
        owner_kind = repository.get("owner_kind")
        owner = str(repository.get("owner", ""))
        name = str(repository.get("name", ""))
        if owner_kind not in {"user", "organization"} or not owner or not SAFE_NAME.fullmatch(owner):
            findings.append(_finding("ambiguous-owner", "required", resource="repository", owner=owner, name=name))
            continue
        if not name or not SAFE_NAME.fullmatch(name):
            findings.append(_finding("unsafe-name", "error", resource="repository", owner=owner, name=name))
            continue
        key = "repository_" + re.sub(r"[^a-z0-9]+", "_", f"{owner}_{name}".casefold()).strip("_")
        if key in repositories:
            findings.append(_finding("duplicate-declaration-key", "error", resource="repository", owner=owner, name=name))
            continue
        entry = {
            "owner": {"user": owner} if owner_kind == "user" else {"organization": owner},
            "name": name,
        }
        entry.update({field: repository[field] for field in REPOSITORY_FIELDS if field in repository})
        repositories[key] = entry
        for unsupported in repository.get("unsupported", []):
            findings.append(_finding("unsupported-state", "required", resource="repository", owner=owner, name=name, field=unsupported))
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
            "repositories": dict(sorted(repositories.items())),
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
    lines += ["  };", "  repositories = {"]
    for key, repository in sorted(gitea.get("repositories", {}).items()):
        fields = " ".join(f"{name} = {nix(repository[name])};" for name in sorted(repository))
        lines.append(f"    {key} = {{ {fields} }};")
    lines += ["  };", "};", ""]
    return "\n".join(lines)


def _declared_repositories(declared: Mapping[str, Any] | Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    values: Any = declared
    if isinstance(declared, Mapping):
        values = declared.get("repositories", declared.get("gitea", {}).get("repositories", []))
    if isinstance(values, Mapping):
        values = list(values.values())
    return sorted((_normalize_repository(item) for item in values), key=lambda item: (_repository_key(item), canonical_json(item)))


def compare_repository_drift(declared: Mapping[str, Any] | Sequence[Mapping[str, Any]], observed: Mapping[str, Any] | Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    """Compare repository metadata without contacting or mutating Gitea."""
    identity_key = lambda item: (str(item.get("owner", "")).casefold(), str(item.get("name", "")).casefold())
    left = {identity_key(item): item for item in _declared_repositories(declared)}
    right = {identity_key(item): item for item in _declared_repositories(observed)}
    changes: list[dict[str, Any]] = []
    for identity in sorted(set(left) | set(right)):
        before, after = left.get(identity), right.get(identity)
        report_identity = [str((after or before).get("owner_kind", "")), *identity]
        if before is None:
            changes.append({"classification": "added", "identity": report_identity, "observed": after})
            continue
        if after is None:
            changes.append({"classification": "removed", "identity": report_identity, "declared": before})
            continue
        for field in REPOSITORY_FIELDS:
            if before.get(field) != after.get(field):
                changes.append({"classification": "modified", "identity": report_identity, "field": field, "declared": before.get(field), "observed": after.get(field)})
        if before.get("owner_kind") != after.get("owner_kind"):
            changes.append({"classification": "owner-conflict", "identity": report_identity, "declared": before.get("owner_kind"), "observed": after.get("owner_kind")})
        for field in after.get("unsupported", []):
            changes.append({"classification": "unsupported", "identity": report_identity, "field": field})
    return {"schema": "osmium.remote-gitea-drift", "version": 1, "complete": not any(item["classification"] == "owner-conflict" for item in changes), "changes": changes}


def convert_drift(document: Mapping[str, Any], secret_files: Mapping[str, str] | None = None) -> dict[str, Any]:
    """Convert observed additions and modifications into the normal candidate shape."""
    observations: dict[tuple[str, str, str], dict[str, Any]] = {}
    for change in document.get("changes", []):
        identity = tuple(change.get("identity", ()))
        if isinstance(change.get("observed"), Mapping):
            observations[identity] = dict(change["observed"])
        elif change.get("classification") == "modified" and len(identity) == 3:
            item = observations.setdefault(identity, {"owner_kind": identity[0], "owner": identity[1], "name": identity[2]})
            item[change.get("field", "")] = change.get("observed")
        elif change.get("classification") == "unsupported" and len(identity) == 3:
            item = observations.setdefault(identity, {"owner_kind": identity[0], "owner": identity[1], "name": identity[2]})
            item.setdefault("unsupported", []).append(change.get("field", "unsupported-state"))
    candidate = convert_capture({**_empty_capture(), "repositories": list(observations.values()), "complete": document.get("complete", False)}, secret_files)
    candidate["source"]["schema"] = document.get("schema", "osmium.remote-gitea-drift")
    return candidate


def _empty_capture() -> dict[str, Any]:
    return {"schema": SCHEMA, "version": SCHEMA_VERSION, "adapter": {"name": ADAPTER, "version": ADAPTER_VERSION}, "source": {"origin": "observed"}, "scope": "gitea", "service": {}, "users": [], "organizations": [], "repositories": [], "persistence": [], "probes": [], "findings": [], "complete": True}


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
            with open(token_file, encoding="utf-8") as handle:
                token = handle.read().strip()
            if not token:
                raise OSError("empty token")
            base = os.environ.get("OSMIUM_GITEA_API_URL", "http://127.0.0.1:3000/api/v1").rstrip("/")
            api_username = os.environ.get("OSMIUM_GITEA_API_USERNAME")

            def pages(endpoint: str) -> list[dict[str, Any]]:
                records = []
                page = 1
                while True:
                    endpoint_url = f"{base}/{endpoint}?limit=50&page={page}"
                    if endpoint == "repos/search":
                        endpoint_url += "&private=true"
                    request = urllib.request.Request(endpoint_url)
                    if api_username:
                        import base64
                        credentials = base64.b64encode(f"{api_username}:{token}".encode()).decode()
                        request.add_header("Authorization", f"Basic {credentials}")
                    else:
                        request.add_header("Authorization", f"token {token}")
                    with urllib.request.urlopen(request, timeout=10) as response:
                        batch = json.load(response)
                    if isinstance(batch, dict) and isinstance(batch.get("data"), list):
                        batch = batch["data"]
                    if not isinstance(batch, list) or any(not isinstance(item, dict) for item in batch):
                        raise ValueError("API returned a non-list")
                    records.extend(batch)
                    if len(batch) < 50:
                        return records
                    page += 1

            users = [{"username": item.get("login", ""), "email": item.get("email", ""), "admin": bool(item.get("is_admin", False)), "source": "local"} for item in pages("admin/users")]
            organizations = [{"name": item.get("username", ""), "description": item.get("description", ""), "visibility": item.get("visibility", ""), "owner": (item.get("owner") or {}).get("login", "")} for item in pages("admin/orgs")]
            repositories = []
            repository_pages = []
            for user in users:
                repository_pages.extend((item, "user") for item in pages(f"users/{user['username']}/repos"))
            for organization in organizations:
                repository_pages.extend((item, "organization") for item in pages(f"orgs/{organization['name']}/repos"))
            if not repository_pages:
                repository_pages = [(item, "organization" if item.get("owner_type") == "Organization" or (item.get("owner") or {}).get("type") == "Organization" else "user") for item in pages("repos/search")]
            for item, owner_kind in repository_pages:
                owner = item.get("owner") or {}
                repositories.append({
                    "owner_kind": owner_kind,
                    "owner": owner.get("login") or owner.get("username") or "",
                    "name": item.get("name", ""),
                    "description": item.get("description", ""),
                    "private": bool(item.get("private", False)),
                    "default_branch": item.get("default_branch", ""),
                    "website": item.get("website", ""),
                    "issues": bool(item.get("has_issues", False)),
                    "wiki": bool(item.get("has_wiki", False)),
                    "pull_requests": bool(item.get("has_pull_requests", False)),
                    "provenance": {"id": item.get("id"), "api": "owner/repos"},
                })
            return {"status": "ok", "users": users, "organizations": organizations, "repositories": repositories, "capabilities": {"repository_fields": list(REPOSITORY_FIELDS), "endpoint": "owner/repos"}}
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
        "repositories": observations["identities"].get("repositories", []),
        "capabilities": observations["identities"].get("capabilities", {}),
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
    drift_convert = sub.add_parser("convert-drift")
    drift_convert.add_argument("input")
    drift_convert.add_argument("--output")
    drift = sub.add_parser("drift")
    drift.add_argument("input")
    drift.add_argument("--output")
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
        elif args.command == "drift":
            source = open(args.input, encoding="utf-8").read()
            value = json.loads(source)
            output = canonical_json(compare_repository_drift(value.get("declared", []), value.get("observed", []))) + "\n"
        elif args.command == "convert-drift":
            source = open(args.input, encoding="utf-8").read()
            output = canonical_json(convert_drift(json.loads(source))) + "\n"
        else:
            source = sys.stdin.read() if args.input == "-" else open(args.input, encoding="utf-8").read()
            document = json.loads(source)
            if args.command == "normalize":
                output = render_capture(document)
            else:
                secret_files = dict(item.split("=", 1) for item in args.secret_file if "=" in item)
                output = canonical_json(convert_capture(document, secret_files)) + "\n"
        if args.command in {"convert", "convert-drift"} and args.output and args.output.endswith(".nix"):
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
