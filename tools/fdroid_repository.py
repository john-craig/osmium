#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import sys
from pathlib import Path


SCHEMA = 1


def read_json(path):
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


def write_json(value, path=None):
    rendered = json.dumps(value, indent=2, sort_keys=True) + "\n"
    if path:
        temporary = f"{path}.tmp"
        with open(temporary, "w", encoding="utf-8") as stream:
            stream.write(rendered)
        os.replace(temporary, path)
    else:
        sys.stdout.write(rendered)


def normalize(observation):
    result = dict(observation)
    result["schema_version"] = SCHEMA
    result["artifacts"] = sorted(
        result.get("artifacts", []), key=lambda item: (item.get("package", ""), item.get("version_code", 0))
    )
    result["findings"] = sorted(result.get("findings", []), key=lambda item: (item.get("code", ""), item.get("message", "")))
    return result


def observe(state, source):
    ledger = read_json(Path(state) / "ledger.json")
    findings = []
    artifacts = []
    for item in ledger.get("artifacts", []):
        artifact = dict(item)
        artifact["provenance"] = {"source": source, "path": str(Path(state) / "repo" / item["file"])}
        artifact_path = Path(state) / "repo" / item["file"]
        if not artifact_path.is_file():
            findings.append({"code": "missing-artifact", "message": item["file"]})
        else:
            artifact["observed_sha256"] = hashlib.sha256(artifact_path.read_bytes()).hexdigest()
            if item.get("sha256") and artifact["observed_sha256"] != item["sha256"]:
                findings.append({"code": "checksum-conflict", "message": item["file"]})
            if not item.get("sha256"):
                artifact["sha256"] = artifact["observed_sha256"]
        artifacts.append(artifact)
    required = ["repository_id", "name", "description", "base_url", "guest_port", "signing"]
    for field in required:
        if not ledger.get(field):
            findings.append({"code": "missing-required-field", "message": field})
    return normalize({
        "schema_version": SCHEMA,
        "source": {"origin": "observed", "kind": source, "state_dir": str(state)},
        "repository": {key: ledger.get(key) for key in required},
        "artifacts": artifacts,
        "findings": findings,
        "complete": not findings,
        "activation_ready": not findings,
    })


def candidate(observation):
    findings = list(observation.get("findings", []))
    repository = observation.get("repository", {})
    declaration = {
        "enable": True,
        "repositoryId": repository.get("repository_id", ""),
        "name": repository.get("name", ""),
        "description": repository.get("description", ""),
        "baseUrl": repository.get("base_url", ""),
        "guestPort": repository.get("guest_port", 0),
        "signing": {
            "keystoreFile": repository.get("signing", {}).get("keystore_file", ""),
            "passwordFile": repository.get("signing", {}).get("password_file", ""),
            "keyAlias": repository.get("signing", {}).get("key_alias", ""),
        },
        "artifacts": {},
    }
    for artifact in observation.get("artifacts", []):
        key = artifact.get("package", "")
        if not key or any(char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" for char in key):
            findings.append({"code": "unsafe-identity", "message": key})
            continue
        declaration["artifacts"][key.replace(".", "_")] = {
            "packageName": key,
            "versionCode": artifact.get("version_code", 0),
            "versionName": artifact.get("version_name", ""),
            "sha256": artifact.get("sha256", ""),
            "path": artifact.get("path", ""),
        }
    findings = sorted(findings, key=lambda item: (item.get("code", ""), item.get("message", "")))
    required_declaration = [
        declaration["repositoryId"],
        declaration["name"],
        declaration["description"],
        declaration["baseUrl"],
        declaration["guestPort"],
        declaration["signing"]["keystoreFile"],
        declaration["signing"]["passwordFile"],
        declaration["signing"]["keyAlias"],
    ]
    if not all(required_declaration):
        findings.append({"code": "missing-required-field", "message": "declarative repository attribute"})
    ready = bool(observation.get("complete")) and not findings
    return {
        "schema_version": SCHEMA,
        "source": observation.get("source", {}),
        "complete": ready,
        "activation_ready": ready,
        "findings": findings,
        "fdroidRepository": declaration,
    }


def main():
    parser = argparse.ArgumentParser(description="Review-only F-Droid repository observation tooling")
    parser.add_argument("command", choices=["observe", "drift", "capture", "convert", "validate", "reconcile"])
    parser.add_argument("--state-dir", default="/var/lib/fdroid-repository")
    parser.add_argument("--input")
    parser.add_argument("--output")
    args = parser.parse_args()
    if args.command in ("observe", "drift"):
        value = observe(args.state_dir, args.command)
    elif args.command == "capture":
        value = observe(args.state_dir, "live-capture")
    elif args.command == "convert":
        value = candidate(read_json(args.input))
    elif args.command == "validate":
        value = read_json(args.input)
        if value.get("schema_version") != SCHEMA or not isinstance(value.get("fdroidRepository"), dict):
            raise SystemExit("candidate is not a supported F-Droid declaration")
        if not value.get("activation_ready", False):
            raise SystemExit("candidate is incomplete and is not ready for activation")
    else:
        value = read_json(args.input)
        if value.get("schema_version") != SCHEMA or not value.get("activation_ready", False):
            raise SystemExit("candidate is incomplete and cannot be reconciled")
        # Reconciliation is deliberately a pure projection, not an activation.
        value = {"schema_version": SCHEMA, "declaration": value["fdroidRepository"]}
    write_json(value, args.output)


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, json.JSONDecodeError) as error:
        print(f"fdroid repository observation failed: {error}", file=sys.stderr)
        raise SystemExit(2)
