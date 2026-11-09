#!/usr/bin/env python3
"""Read-only Traefik observation and review-only candidate conversion."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Mapping

SCHEMA = "osmium.traefik-observation"
VERSION = 1
SECRET = re.compile(r"(?:password|passwd|secret|token|api[_-]?key|private[_-]?key|access[_-]?key)", re.I)
REFERENCE = re.compile(r"(?:cert|key|secret|credential|env|file|ca)[_-]?(?:file|path)?$", re.I)


class ObservationError(RuntimeError):
    pass


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def clean(value: Any, key: str = "") -> Any:
    if isinstance(value, Mapping):
        result = {}
        for name in sorted(value, key=str):
            name = str(name)
            item = value[name]
            if SECRET.search(name):
                result[name] = {"present": bool(item), "redacted": True}
            elif isinstance(item, str) and REFERENCE.search(name):
                result[name] = {"reference": item}
            else:
                result[name] = clean(item, name)
        return result
    if isinstance(value, list):
        return [clean(item, key) for item in value]
    if isinstance(value, str):
        return value.replace("\x00", "")
    if value is None or isinstance(value, (bool, int, float)):
        return value
    raise ObservationError(f"unsupported value at {key or 'document'}")


def read_file(path: str | None) -> dict[str, Any] | None:
    if path is None:
        return None
    data = Path(path).read_bytes()
    result: dict[str, Any] = {
        "path": path,
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
    }
    try:
        result["configuration"] = clean(json.loads(data))
    except (UnicodeDecodeError, json.JSONDecodeError):
        result["unsupported"] = "configuration is not JSON; source content was not exported"
    return result


def get_json(url: str) -> Any:
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.loads(response.read())
    except (OSError, ValueError, urllib.error.URLError) as error:
        raise ObservationError(f"cannot observe Traefik API {url}: {error}") from error


def observe(api_url: str, static_file: str | None, dynamic_file: str | None) -> dict[str, Any]:
    api_url = api_url.rstrip("/")
    findings: list[dict[str, Any]] = []
    runtime: dict[str, Any] = {}
    for name, endpoint in {
        "overview": "/overview",
        "entrypoints": "/entrypoints",
        "routers": "/http/routers",
        "services": "/http/services",
        "middlewares": "/http/middlewares",
    }.items():
        try:
            runtime[name] = clean(get_json(api_url + endpoint))
        except ObservationError as error:
            runtime[name] = []
            findings.append({"code": "runtime-observation-failed", "severity": "required", "endpoint": endpoint, "message": str(error)})

    for collection in ("routers", "services", "middlewares"):
        for item in runtime[collection] if isinstance(runtime[collection], list) else []:
            provider = item.get("provider") if isinstance(item, Mapping) else None
            if provider and provider != "file":
                findings.append({"code": "provider-generated-object", "severity": "required", "resource": collection, "name": item.get("name"), "provider": provider})

    sources = {"static": read_file(static_file), "dynamic": read_file(dynamic_file)}
    for name, source in sources.items():
        if source and "unsupported" in source:
            findings.append({"code": "unreadable-source-format", "severity": "required", "source": name})
    complete = not findings
    return {
        "schema": SCHEMA,
        "version": VERSION,
        "service": "traefik",
        "source": {"api": api_url, "static_file": static_file, "dynamic_file": dynamic_file},
        "sources": sources,
        "runtime": runtime,
        "findings": sorted(findings, key=canonical),
        "complete": complete,
        "mutation": {"performed": False, "source_files_changed": False, "runtime_changed": False},
    }


def nix(value: Any, indent: int = 0) -> str:
    if isinstance(value, Mapping):
        if not value:
            return "{ }"
        pad = " " * indent
        child = " " * (indent + 2)
        lines = ["{"]
        for key in sorted(value, key=str):
            name = str(key) if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_'-]*", str(key)) else json.dumps(str(key))
            lines.append(f"{child}{name} = {nix(value[key], indent + 2)};")
        lines.append(pad + "}")
        return "\n".join(lines)
    if isinstance(value, list):
        return "[ " + " ".join(nix(item, indent) for item in value) + " ]"
    if isinstance(value, str):
        return json.dumps(value)
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "null"
    return str(value)


def candidate(document: Mapping[str, Any], mode: str) -> dict[str, Any]:
    findings = list(document.get("findings", []))
    dynamic = ((document.get("sources") or {}).get("dynamic") or {}).get("configuration")
    if not isinstance(dynamic, Mapping):
        findings.append({"code": "dynamic-source-unavailable", "severity": "required"})
        dynamic = {}
    candidate_value = {
        "dynamicConfigOptions": dynamic,
        "source": document.get("source", {}),
        "mode": mode,
        "complete": bool(document.get("complete")) and not findings,
        "findings": sorted(findings, key=canonical),
        "provenance": {"schema": SCHEMA, "derived_from": "runtime-observation-and-source-files"},
    }
    candidate_value["nix"] = "# Review-only candidate; do not activate blindly.\nservices.osmium.traefik.dynamicConfigOptions = " + nix(dynamic) + ";\n"
    return candidate_value


def drift(observed: Mapping[str, Any], declared: Mapping[str, Any]) -> dict[str, Any]:
    observed_dynamic = ((observed.get("sources") or {}).get("dynamic") or {}).get("configuration") or {}
    declared_dynamic = declared.get("dynamicConfigOptions") or declared.get("dynamic_config_options") or {}
    changes = []
    if canonical(observed_dynamic) != canonical(declared_dynamic):
        changes.append({"code": "dynamic-configuration-drift", "severity": "required", "provenance": observed.get("source", {})})
    result = candidate(observed, "drift")
    result["changes"] = changes
    result["complete"] = bool(result["complete"] and not changes)
    return result


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("observe", "capture"):
        command = sub.add_parser(name)
        command.add_argument("--api-url", default="http://127.0.0.1:8081/api")
        command.add_argument("--static-file")
        command.add_argument("--dynamic-file")
        command.add_argument("--output", required=True)
    drift_parser = sub.add_parser("drift")
    drift_parser.add_argument("--observation", required=True)
    drift_parser.add_argument("--declared", required=True)
    drift_parser.add_argument("--output", required=True)

    args = parser.parse_args(argv)
    try:
        if args.command in {"observe", "capture"}:
            document = observe(args.api_url, args.static_file, args.dynamic_file)
            if args.command == "capture":
                document["capture"] = candidate(document, "live-capture")
        else:
            document = drift(json.loads(Path(args.observation).read_text()), json.loads(Path(args.declared).read_text()))
        Path(args.output).write_text(canonical(document) + "\n")
    except (OSError, json.JSONDecodeError, ObservationError) as error:
        print(f"osmium-traefik-observe: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
