#!/usr/bin/env python3
"""Schemas and deterministic wire-format helpers for filesystem snapshots.

This module deliberately has no Btrfs or NixOS dependencies.  Later lifecycle,
comparison, and deployment code can use these contracts without importing a
service module or relying on platform-specific path string handling.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import fnmatch
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import time
from collections.abc import Mapping, Sequence
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
SCHEMAS = {
    "canonical-tree": "osmium.filesystem.canonical-tree",
    "drift-report": "osmium.filesystem.drift-report",
    "snapshot-metadata": "osmium.filesystem.snapshot-metadata",
    "reconstruction-bundle": "osmium.filesystem.reconstruction-bundle",
}

EXIT_STATUS = {
    "clean": (0, "clean"),
    "drift": (10, "drift-detected"),
    "incomplete-export": (20, "incomplete-export"),
    "validation-error": (30, "validation-error"),
    "operational-error": (40, "operational-error"),
}

_TYPES = {"directory", "regular", "symlink", "fifo", "socket", "device"}
_COMMON_ENTRY_KEYS = {
    "path", "type", "mode", "uid", "gid", "mtime_ns", "xattrs", "hard_link_id"
}
_ENTRY_KEYS = {
    "directory": _COMMON_ENTRY_KEYS,
    "regular": _COMMON_ENTRY_KEYS | {"size", "sha256"},
    "symlink": _COMMON_ENTRY_KEYS | {"target"},
    "fifo": _COMMON_ENTRY_KEYS,
    "socket": _COMMON_ENTRY_KEYS,
    "device": _COMMON_ENTRY_KEYS | {"major", "minor"},
}


class SchemaError(ValueError):
    """Raised when a wire-format document is not valid."""


class SnapshotError(RuntimeError):
    """Raised when a managed snapshot cannot be safely used."""


def _atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    data = canonical_json(value)
    try:
        with temporary.open("wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        with contextlib.suppress(FileNotFoundError):
            temporary.unlink()


def atomic_write(path: str | bytes | Path, data: bytes, *, mode: int = 0o640,
                 uid: int | None = None, gid: int | None = None) -> None:
    """Write an administrative artifact without exposing a partial result."""
    destination = Path(os.fsdecode(os_path_bytes(path)))
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.{os.getpid()}.tmp")
    try:
        with temporary.open("wb") as stream:
            os.fchmod(stream.fileno(), mode)
            if uid is not None or gid is not None:
                os.fchown(stream.fileno(), -1 if uid is None else uid, -1 if gid is None else gid)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
        directory = os.open(destination.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        with contextlib.suppress(FileNotFoundError):
            temporary.unlink()


class HashCache:
    """A cache whose entries are valid only for one validated immutable tree."""

    def __init__(self, directory: str | bytes | Path):
        self.directory = Path(os.fsdecode(os_path_bytes(directory)))

    def _path(self, identity: str, encoded_path: str) -> Path:
        key = hashlib.sha256(f"{identity}\0{encoded_path}".encode("ascii")).hexdigest()
        return self.directory / f"{key}.json"

    def get(self, identity: str, encoded_path: str, metadata: Mapping[str, Any],
            *, immutable: bool = False) -> str | None:
        if not immutable:
            return None
        path = self._path(identity, encoded_path)
        if not path.exists():
            return None
        try:
            value = _read_json(path)
            if value.get("identity") != identity or value.get("metadata") != dict(metadata):
                return None
            digest = value.get("sha256")
            if not isinstance(digest, str) or len(digest) != 64:
                return None
            return digest
        except (SnapshotError, AttributeError):
            return None

    def put(self, identity: str, encoded_path: str, metadata: Mapping[str, Any],
            digest: str, *, immutable: bool = False) -> None:
        if not immutable:
            return
        _atomic_json(self._path(identity, encoded_path), {
            "identity": identity, "metadata": dict(metadata), "sha256": digest,
        })


def _parse_btrfs_value(output: bytes, label: str) -> str:
    match = re.search(rb"^\s*" + re.escape(label.encode()) + rb"\s*:\s*(\S+)", output, re.MULTILINE)
    if not match:
        raise SnapshotError(f"btrfs output has no {label}")
    return match.group(1).decode("ascii")


def _btrfs_uuid(runner: Any, path: Path) -> tuple[str, str | None]:
    result = runner(["btrfs", "subvolume", "show", "--", os.fsencode(path)])
    if result.returncode:
        raise SnapshotError(f"cannot inspect snapshot {path}")
    snapshot_id = _parse_btrfs_value(result.stdout, "UUID")
    parent = re.search(rb"^\s*Parent UUID\s*:\s*(\S+)", result.stdout, re.MULTILINE)
    parent_id = parent.group(1).decode("ascii") if parent else None
    return snapshot_id, None if parent_id in (None, "-") else parent_id


def _is_read_only(runner: Any, path: Path) -> bool:
    result = runner(["btrfs", "property", "get", "-ts", os.fsencode(path), "ro"])
    if result.returncode:
        raise SnapshotError(f"cannot inspect read-only property for {path}")
    return bool(re.search(rb"(?:^|\s)ro=true(?:\s|$)", result.stdout.strip()))


def _read_json(path: Path) -> Any:
    try:
        with path.open("rb") as stream:
            return json.load(stream)
    except (OSError, ValueError) as error:
        raise SnapshotError(f"cannot read managed state {path}") from error


class SnapshotManager:
    """Create and retain read-only Btrfs snapshots for one tracker.

    The command runner receives argv with bytes for filesystem paths. This makes
    the implementation testable and avoids lossy conversion of arbitrary paths.
    """

    def __init__(self, source: str | bytes, snapshot_root: str | bytes, state_dir: str | bytes | None = None, runner: Any = None):
        self.source = Path(os.fsdecode(os_path_bytes(source)))
        self.root = Path(os.fsdecode(os_path_bytes(snapshot_root)))
        self.state = Path(os.fsdecode(os_path_bytes(state_dir))) if state_dir is not None else self.root / ".osmium"
        self.runner = runner or self._subprocess_runner

    @staticmethod
    def _subprocess_runner(argv: Sequence[Any]) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)

    @property
    def _metadata_dir(self) -> Path:
        return self.state / "snapshots"

    @property
    def _tracker_state(self) -> Path:
        return self.state / "state.json"

    @contextlib.contextmanager
    def _lock(self):
        self.state.mkdir(parents=True, exist_ok=True)
        with (self.state / "operations.lock").open("a+b") as stream:
            import fcntl
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)

    def _state_value(self) -> dict[str, Any]:
        if not self._tracker_state.exists():
            return {"current_baseline": None, "active_references": []}
        value = _read_json(self._tracker_state)
        if not isinstance(value, dict) or not isinstance(value.get("active_references", []), list):
            raise SnapshotError("malformed tracker state")
        return value

    def _source_id(self) -> str:
        source_id, parent = _btrfs_uuid(self.runner, self.source)
        if parent is not None:
            raise SnapshotError("configured source is not a top-level source subvolume")
        return source_id

    def _validate_record(self, record: Mapping[str, Any]) -> None:
        validate_document(record["metadata"], "snapshot-metadata")
        snapshot_path = Path(os.fsdecode(record["path"]))
        if not snapshot_path.is_dir() or not os.access(snapshot_path, os.R_OK | os.X_OK):
            raise SnapshotError(f"snapshot is missing or inaccessible: {snapshot_path}")
        actual_id, parent_id = _btrfs_uuid(self.runner, snapshot_path)
        if actual_id != record["metadata"]["snapshot_id"]:
            raise SnapshotError(f"snapshot identity mismatch: {snapshot_path}")
        if record["metadata"]["source_id"] != self._source_id() or parent_id != self._source_id():
            raise SnapshotError(f"snapshot lineage mismatch: {snapshot_path}")
        if not record["metadata"]["read_only"] or not _is_read_only(self.runner, snapshot_path):
            raise SnapshotError(f"snapshot is writable: {snapshot_path}")
        if not record["metadata"]["complete"] or not record.get("complete", False):
            raise SnapshotError(f"snapshot is incomplete: {snapshot_path}")

    def _create(self, role: str) -> dict[str, Any]:
        source_id = self._source_id()
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        destination = self.root / f"{role}-{timestamp}-{os.getpid()}"
        self.root.mkdir(parents=True, exist_ok=True)
        result = self.runner(["btrfs", "subvolume", "snapshot", "-r", os.fsencode(self.source), os.fsencode(destination)])
        if result.returncode:
            raise SnapshotError(f"cannot create {role} snapshot")
        try:
            snapshot_id, parent_id = _btrfs_uuid(self.runner, destination)
            metadata = {"schema": SCHEMAS["snapshot-metadata"], "version": SCHEMA_VERSION, "snapshot_id": snapshot_id, "source_id": source_id, "role": role, "created_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "read_only": parent_id == source_id and _is_read_only(self.runner, destination), "complete": True}
            record = {"metadata": metadata, "path": os.fsencode(destination).decode("utf-8", "surrogateescape"), "complete": True}
            self._validate_record(record)
            _atomic_json(self._metadata_dir / f"{snapshot_id}.json", record)
            return record
        except Exception:
            self.runner(["btrfs", "subvolume", "delete", "--", os.fsencode(destination)])
            raise

    def baseline(self) -> dict[str, Any]:
        with self._lock():
            state = self._state_value()
            if state.get("current_baseline"):
                record = _read_json(self._metadata_dir / f"{state['current_baseline']}.json")
                self._validate_record(record)
                return record
            record = self._create("baseline")
            state["current_baseline"] = record["metadata"]["snapshot_id"]
            _atomic_json(self._tracker_state, state)
            return record

    def observe(self) -> dict[str, Any]:
        with self._lock():
            state = self._state_value()
            if not state.get("current_baseline"):
                raise SnapshotError("cannot observe without a baseline")
            baseline = _read_json(self._metadata_dir / f"{state['current_baseline']}.json")
            self._validate_record(baseline)
            return self._create("observation")

    def report(self, snapshot_id: str, *, threshold: int = 1024 * 1024,
               exclusions: Sequence[bytes | str] = (), redactions: Sequence[bytes | str] = (),
               cache: HashCache | None = None) -> dict[str, Any]:
        with self._lock():
            state = self._state_value()
            baseline_id = state.get("current_baseline")
            if not baseline_id:
                raise SnapshotError("cannot report without a baseline")
            baseline = _read_json(self._metadata_dir / f"{baseline_id}.json")
            observation = _read_json(self._metadata_dir / f"{snapshot_id}.json")
            self._validate_record(baseline)
            self._validate_record(observation)
            report = compare_trees(
                baseline["path"], observation["path"], threshold,
                exclusions, redactions,
                baseline_identity=baseline_id, observation_identity=snapshot_id,
                cache=cache, immutable=True,
            )
            report["baseline_snapshot"] = baseline_id
            report["observation_snapshot"] = snapshot_id
            validate_document(report, "drift-report")
            return report

    def latest_observation(self) -> str:
        records = []
        for path in self._metadata_dir.glob("*.json"):
            record = _read_json(path)
            if record.get("metadata", {}).get("role") == "observation" and record.get("complete"):
                records.append(record)
        if not records:
            raise SnapshotError("no completed observation exists")
        return max(records, key=lambda item: item["metadata"]["created_at"])["metadata"]["snapshot_id"]

    def promote(self, snapshot_id: str) -> dict[str, Any]:
        with self._lock():
            record = _read_json(self._metadata_dir / f"{snapshot_id}.json")
            if record.get("metadata", {}).get("role") != "observation":
                raise SnapshotError("only an observation can be promoted")
            self._validate_record(record)
            state = self._state_value()
            previous_id = state.get("current_baseline")
            if previous_id and previous_id != snapshot_id:
                previous_path = self._metadata_dir / f"{previous_id}.json"
                previous = _read_json(previous_path)
                previous["metadata"]["role"] = "observation"
                _atomic_json(previous_path, previous)
            record["metadata"]["role"] = "baseline"
            _atomic_json(self._metadata_dir / f"{snapshot_id}.json", record)
            state["current_baseline"] = snapshot_id
            _atomic_json(self._tracker_state, state)
            return record

    def retain(self, count: int | None = None, age: int | None = None, now: float | None = None) -> list[str]:
        if count is None and age is None:
            raise ValueError("count or age is required")
        with self._lock():
            state = self._state_value()
            protected = {state.get("current_baseline"), *state.get("active_references", [])}
            records = [_read_json(path) for path in sorted(self._metadata_dir.glob("*.json"))]
            completed = [record for record in records if record.get("complete") and record.get("metadata", {}).get("complete")]
            current = time.time() if now is None else now
            remove: list[dict[str, Any]] = []
            for record in sorted(completed, key=lambda item: item["metadata"]["created_at"]):
                snapshot_id = record["metadata"]["snapshot_id"]
                too_old = age is not None and current - datetime.fromisoformat(record["metadata"]["created_at"].replace("Z", "+00:00")).timestamp() > age
                too_many = count is not None and len(completed) - len(remove) > count
                if snapshot_id not in protected and (too_old or too_many):
                    remove.append(record)
            for record in remove:
                path = Path(os.fsdecode(record["path"]))
                result = self.runner(["btrfs", "subvolume", "delete", "--", os.fsencode(path)])
                if result.returncode:
                    raise SnapshotError(f"cannot remove snapshot {path}")
                (self._metadata_dir / f"{record['metadata']['snapshot_id']}.json").unlink()
            return [record["metadata"]["snapshot_id"] for record in remove]


def encode_path(path: bytes | str) -> str:
    """Encode one relative path as unpadded URL-safe base64."""
    raw = os_path_bytes(path)
    if not raw or raw.startswith(b"/") or b"\x00" in raw:
        raise SchemaError("path must be non-empty, relative, and NUL-free")
    parts = raw.split(b"/")
    if any(part in (b"", b".", b"..") for part in parts):
        raise SchemaError("path contains an empty, '.' or '..' component")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def decode_path(encoded: str) -> bytes:
    if not isinstance(encoded, str) or not encoded:
        raise SchemaError("path must be a non-empty base64 string")
    try:
        raw = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
    except (ValueError, base64.binascii.Error) as error:
        raise SchemaError("path is not valid base64url") from error
    # Re-encoding rejects alternate spellings and makes ordering unambiguous.
    if encode_path(raw) != encoded:
        raise SchemaError("path is not canonical base64url")
    return raw


def os_path_bytes(path: bytes | str) -> bytes:
    if isinstance(path, bytes):
        return path
    if isinstance(path, str):
        return path.encode("utf-8", "surrogateescape")
    if isinstance(path, os.PathLike):
        return os_path_bytes(os.fspath(path))
    raise SchemaError("path must be bytes or string")


def encode_bytes(value: bytes | str) -> str:
    """Encode arbitrary bytes as canonical, unpadded base64url."""
    return base64.urlsafe_b64encode(os_path_bytes(value)).decode("ascii").rstrip("=")


def decode_bytes(value: str) -> bytes:
    if not isinstance(value, str):
        raise SchemaError("encoded bytes must be a string")
    try:
        raw = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    except (ValueError, base64.binascii.Error) as error:
        raise SchemaError("encoded bytes are not valid base64url") from error
    if encode_bytes(raw) != value:
        raise SchemaError("encoded bytes are not canonical base64url")
    return raw


def canonical_json(value: Any) -> bytes:
    """Serialize a document deterministically, including a trailing newline."""
    return (json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n").encode("ascii")


def _require_object(value: Any, name: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise SchemaError(f"{name} must be an object")
    return value


def _require_int(value: Any, name: str, minimum: int | None = None) -> None:
    if isinstance(value, bool) or not isinstance(value, int) or (minimum is not None and value < minimum):
        raise SchemaError(f"{name} must be an integer")


def _check_header(document: Mapping[str, Any], kind: str) -> None:
    if document.get("schema") != SCHEMAS[kind] or document.get("version") != SCHEMA_VERSION:
        raise SchemaError(f"unsupported {kind} schema or version")


def validate_entry(entry: Any) -> None:
    item = _require_object(entry, "entry")
    object_type = item.get("type")
    if object_type not in _TYPES:
        raise SchemaError("entry has an unsupported type")
    if set(item) - _ENTRY_KEYS[object_type] or not _COMMON_ENTRY_KEYS <= set(item):
        raise SchemaError("entry has missing or unknown fields")
    decode_path(item["path"])
    for field in ("mode", "uid", "gid", "mtime_ns"):
        _require_int(item[field], field, 0)
    if item["xattrs"] is not None:
        xattrs = _require_object(item["xattrs"], "xattrs")
        if any(not isinstance(k, str) or not isinstance(v, str) for k, v in xattrs.items()):
            raise SchemaError("xattrs must map names to base64 strings")
    if item["hard_link_id"] is not None and not isinstance(item["hard_link_id"], str):
        raise SchemaError("hard_link_id must be a string or null")
    if object_type == "regular":
        _require_int(item["size"], "size", 0)
        if not isinstance(item["sha256"], str) or len(item["sha256"]) != 64:
            raise SchemaError("regular entry has an invalid sha256")
    if object_type == "symlink":
        decode_bytes(item["target"])
    if object_type == "device":
        _require_int(item["major"], "major", 0)
        _require_int(item["minor"], "minor", 0)


def validate_document(document: Any, kind: str) -> None:
    if kind not in SCHEMAS:
        raise SchemaError(f"unknown document kind: {kind}")
    value = _require_object(document, kind)
    _check_header(value, kind)
    if kind == "canonical-tree":
        if set(value) != {"schema", "version", "entries"} or not isinstance(value["entries"], list):
            raise SchemaError("canonical tree must contain only entries")
        for entry in value["entries"]:
            validate_entry(entry)
        paths = [entry["path"] for entry in value["entries"]]
        if paths != sorted(paths) or len(paths) != len(set(paths)):
            raise SchemaError("canonical entries must be unique and sorted")
    elif kind == "snapshot-metadata":
        expected = {"schema", "version", "snapshot_id", "source_id", "role", "created_at", "read_only", "complete"}
        if set(value) != expected or value["role"] not in {"baseline", "observation"}:
            raise SchemaError("invalid snapshot metadata fields")
        for field in ("snapshot_id", "source_id", "created_at"):
            if not isinstance(value[field], str) or not value[field]:
                raise SchemaError(f"{field} must be a non-empty string")
        if not isinstance(value["read_only"], bool) or not isinstance(value["complete"], bool):
            raise SchemaError("snapshot flags must be boolean")
    elif kind == "drift-report":
        expected = {"schema", "version", "baseline_snapshot", "observation_snapshot", "status", "changes", "metadata"}
        if set(value) != expected or value["status"] not in {"clean", "drift", "operational-error"}:
            raise SchemaError("invalid drift report fields")
        if not isinstance(value["changes"], list) or not isinstance(value["metadata"], Mapping):
            raise SchemaError("invalid drift report collections")
        for change in value["changes"]:
            if not isinstance(change, Mapping) or set(change) - {"path", "classification", "old", "new", "reasons", "content"}:
                raise SchemaError("malformed drift change")
            if not isinstance(change.get("path"), str):
                raise SchemaError("drift changes require encoded paths")
            decode_path(change["path"])
            if "classification" in change and change["classification"] not in {
                "added", "removed", "content-modified", "metadata-modified",
                "link-target-modified", "type-changed", "unchanged",
            }:
                raise SchemaError("invalid drift classification")
            if "reasons" in change and (
                not isinstance(change["reasons"], list)
                or any(not isinstance(reason, str) for reason in change["reasons"])
            ):
                raise SchemaError("drift reasons must be strings")
            if "content" in change:
                content = _require_object(change["content"], "content")
                if set(content) != {"encoding", "data"} or content["encoding"] != "base64" or not isinstance(content["data"], str):
                    raise SchemaError("content must be a base64 representation")
                decode_bytes(content["data"])
        if [c["path"] for c in value["changes"]] != sorted(c["path"] for c in value["changes"]):
            raise SchemaError("drift changes must be sorted")
    elif kind == "reconstruction-bundle":
        expected = {"schema", "version", "baseline_snapshot", "observed_snapshot", "complete", "operations", "incomplete"}
        optional = {"manifest", "payloads"}
        if set(value) - expected - optional or not expected <= set(value) or not isinstance(value["operations"], list) or not isinstance(value["incomplete"], list):
            raise SchemaError("invalid reconstruction bundle fields")
        if not isinstance(value["complete"], bool) or any(
            not isinstance(item, Mapping)
            or set(item) - {"path", "reason", "detail"}
            or not isinstance(item.get("path"), str)
            or not isinstance(item.get("reason"), str)
            for item in value["incomplete"]
        ):
            raise SchemaError("invalid reconstruction bundle completeness")
        for item in value["incomplete"]:
            decode_path(item["path"])
        if "manifest" in value:
            validate_document(value["manifest"], "canonical-tree")
        if "payloads" in value:
            if not isinstance(value["payloads"], Mapping) or any(
                not isinstance(key, str) or not re.fullmatch(r"[0-9a-f]{64}", key)
                or not isinstance(payload, str) for key, payload in value["payloads"].items()
            ):
                raise SchemaError("invalid bundle payloads")
        for operation in value["operations"]:
            if not isinstance(operation, Mapping) or set(operation) - {
                "path", "action", "type", "metadata", "payload", "expected_sha256", "result_sha256"
            } or not isinstance(operation.get("path"), str):
                raise SchemaError("malformed reconstruction operation")
            decode_path(operation["path"])
            if operation.get("action") not in {"create", "replace", "metadata", "link", "remove"}:
                raise SchemaError("invalid reconstruction operation")
            if operation.get("type") not in _TYPES:
                raise SchemaError("reconstruction operation has an unsupported type")
            if operation.get("action") == "remove" and operation.get("type") is None:
                raise SchemaError("remove operation requires a type")
            if "payload" in operation and (
                not isinstance(operation["payload"], str)
                or not re.fullmatch(r"[0-9a-f]{64}", operation["payload"])
            ):
                raise SchemaError("invalid operation payload")
        paths = [item.get("path") for item in value["operations"]]
        keys = [_operation_key(item) for item in value["operations"]]
        if any(not isinstance(path, str) for path in paths) or keys != sorted(keys):
            raise SchemaError("bundle operations must have deterministic ordering")


def status_for(document: Mapping[str, Any]) -> tuple[int, str]:
    """Return the stable process result for a validated report or bundle."""
    if document.get("schema") == SCHEMAS["drift-report"]:
        return EXIT_STATUS[document["status"]]
    if document.get("schema") == SCHEMAS["reconstruction-bundle"]:
        return EXIT_STATUS["clean" if document["complete"] else "incomplete-export"]
    raise SchemaError("status requires a drift report or reconstruction bundle")


def _operation_key(operation: Mapping[str, Any]) -> tuple[int, int, str]:
    """Create parents first and remove children first, deterministically."""
    action_order = {"create": 0, "replace": 1, "link": 2, "metadata": 3, "remove": 4}
    depth = len(decode_path(operation["path"]).split(b"/"))
    return (action_order[operation["action"]], -depth if operation["action"] == "remove" else depth, operation["path"])


def export_bundle(report: Mapping[str, Any], observed_manifest: Mapping[str, Any] | None = None,
                  *, payload_dir: str | bytes | Path | None = None) -> dict[str, Any]:
    """Render a deterministic reconstruction bundle from a drift report.

    Payloads are stored inline as base64 in the bundle and, when requested, as
    raw content-addressed files named by their SHA-256 digest.
    """
    validate_document(report, "drift-report")
    if observed_manifest is None:
        candidate = report.get("metadata", {}).get("observed_manifest")
        if candidate is not None:
            observed_manifest = candidate
    operations: list[dict[str, Any]] = []
    incomplete: list[dict[str, Any]] = []
    payloads: dict[str, str] = {}
    for change in report["changes"]:
        path = change["path"]
        old, new = change.get("old"), change.get("new")
        target = new or old
        if target is None or target.get("type") not in {"directory", "regular", "symlink", "fifo"}:
            incomplete.append({"path": path, "reason": "unsupported-object", "detail": target.get("type") if target else "missing-state"})
            continue
        classification = change["classification"]
        if classification == "removed":
            operations.append({"path": path, "action": "remove", "type": old["type"], "expected_sha256": old.get("sha256")})
            continue
        action = "create" if classification in {"added", "type-changed"} else (
            "replace" if classification == "content-modified" else
            "link" if classification == "link-target-modified" else "metadata")
        if classification == "type-changed":
            if old.get("type") not in {"directory", "regular", "symlink", "fifo"}:
                incomplete.append({"path": path, "reason": "unsupported-object", "detail": old.get("type")})
                continue
            operations.append({"path": path, "action": "remove", "type": old["type"], "expected_sha256": old.get("sha256")})
        operation: dict[str, Any] = {"path": path, "action": action, "type": new["type"], "metadata": new,
                                     "expected_sha256": old.get("sha256") if old else None,
                                     "result_sha256": new.get("sha256") if new else None}
        content = change.get("content")
        if new["type"] == "regular" and action in {"create", "replace"}:
            if content is None:
                reason = next((reason for reason in change.get("reasons", []) if reason in {"content-diff-omitted", "content-redacted"}), "content-missing")
                incomplete.append({"path": path, "reason": reason})
                continue
            raw = decode_bytes(content["data"])
            digest = hashlib.sha256(raw).hexdigest()
            if digest != new["sha256"]:
                raise SchemaError(f"content hash does not match observed entry: {path}")
            payloads.setdefault(digest, content["data"])
            operation["payload"] = digest
        operations.append(operation)
    operations.sort(key=_operation_key)
    bundle: dict[str, Any] = {"schema": SCHEMAS["reconstruction-bundle"], "version": SCHEMA_VERSION,
                              "baseline_snapshot": report["baseline_snapshot"],
                              "observed_snapshot": report["observation_snapshot"],
                              "complete": not incomplete, "operations": operations, "incomplete": sorted(incomplete, key=lambda item: (item["path"], item["reason"]))}
    if observed_manifest is not None:
        validate_document(observed_manifest, "canonical-tree")
        bundle["manifest"] = observed_manifest
    if payloads:
        bundle["payloads"] = payloads
        if payload_dir is not None:
            directory = Path(os.fsdecode(os_path_bytes(payload_dir)))
            for digest, encoded in payloads.items():
                atomic_write(directory / digest, decode_bytes(encoded), mode=0o600)
    validate_document(bundle, "reconstruction-bundle")
    return bundle


def validate_bundle(bundle: Mapping[str, Any], destination: str | bytes | Path, *, payload_dir: str | bytes | Path | None = None,
                    allow_incomplete: bool = False) -> None:
    """Perform all checks that must pass before deployment mutates a tree."""
    validate_document(bundle, "reconstruction-bundle")
    if bundle["incomplete"] and not allow_incomplete:
        raise SchemaError("incomplete reconstruction bundle")
    root = os.path.abspath(os_path_bytes(destination))
    payload_root = os.path.abspath(os_path_bytes(payload_dir)) if payload_dir is not None else None
    payloads = bundle.get("payloads", {})
    for operation in bundle["operations"]:
        relative = decode_path(operation["path"])
        target = os.path.abspath(os.path.join(root, relative))
        if os.path.commonpath((root, target)) != root:
            raise SchemaError("operation path escapes destination")
        if operation["action"] == "create" and os.path.lexists(target):
            raise SchemaError(f"create precondition already exists: {operation['path']}")
        parent = os.path.dirname(target)
        while parent != root and os.path.lexists(parent):
            if os.path.commonpath((root, os.path.realpath(parent))) != root:
                raise SchemaError("operation parent escapes destination")
            parent = os.path.dirname(parent)
        if operation.get("payload"):
            digest = operation["payload"]
            encoded = payloads.get(digest)
            if encoded is not None:
                data = decode_bytes(encoded)
            elif payload_root is not None:
                try:
                    with open(os.path.join(payload_root, digest), "rb") as stream:
                        data = stream.read()
                except OSError as error:
                    raise SchemaError(f"missing payload: {digest}") from error
            else:
                raise SchemaError(f"missing payload: {digest}")
            if hashlib.sha256(data).hexdigest() != digest or hashlib.sha256(data).hexdigest() != operation.get("result_sha256"):
                raise SchemaError(f"payload hash mismatch: {operation['path']}")
        if operation["action"] in {"replace", "metadata", "link", "remove"}:
            if not os.path.lexists(target):
                raise SchemaError(f"baseline precondition missing: {operation['path']}")
            expected = operation.get("expected_sha256")
            if expected and (not stat.S_ISREG(os.lstat(target).st_mode) or _file_hash(os.fsencode(target)) != expected):
                raise SchemaError(f"baseline precondition mismatch: {operation['path']}")


def _file_hash(path: bytes) -> str:
    digest = hashlib.sha256()
    with open(path, "rb", buffering=0) as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def deploy_bundle(bundle: Mapping[str, Any], destination: str | bytes | Path, *, payload_dir: str | bytes | Path | None = None) -> None:
    """Validate, then explicitly apply a complete bundle beneath destination."""
    validate_bundle(bundle, destination, payload_dir=payload_dir)
    root = os_path_bytes(destination)
    os.makedirs(root, exist_ok=True)
    payloads = bundle.get("payloads", {})
    hard_links: dict[str, bytes] = {}
    for operation in bundle["operations"]:
        target = os.path.join(root, decode_path(operation["path"]))
        action, kind = operation["action"], operation["type"]
        if action == "remove":
            if os.path.isdir(target) and not os.path.islink(target):
                os.rmdir(target)
            else:
                os.unlink(target)
            continue
        metadata = operation.get("metadata", {})
        if action in {"create", "replace"} and kind == "directory":
            os.makedirs(target, exist_ok=True)
        elif kind == "regular" and action in {"create", "replace"}:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            hard_link_id = metadata.get("hard_link_id")
            if action == "create" and hard_link_id in hard_links:
                os.link(hard_links[hard_link_id], target)
            else:
                data = decode_bytes(payloads[operation["payload"]]) if operation.get("payload") in payloads else Path(os.fsdecode(os.path.join(os_path_bytes(payload_dir), operation["payload"]))).read_bytes()
                atomic_write(target, data, mode=0o600)
                if action == "create" and hard_link_id is not None:
                    hard_links[hard_link_id] = target
        elif kind == "symlink":
            os.makedirs(os.path.dirname(target), exist_ok=True)
            if os.path.lexists(target): os.unlink(target)
            os.symlink(decode_bytes(metadata["target"]), target)
        elif kind == "fifo":
            os.makedirs(os.path.dirname(target), exist_ok=True)
            if not os.path.exists(target): os.mkfifo(target)
        if action in {"create", "replace", "metadata", "link"}:
            if kind != "symlink":
                os.chmod(target, metadata["mode"])
                os.chown(target, metadata["uid"], metadata["gid"])
            os.utime(target, ns=(metadata["mtime_ns"], metadata["mtime_ns"]), follow_symlinks=False)
            desired_xattrs = metadata.get("xattrs") or {}
            for name in os.listxattr(target, follow_symlinks=False):
                if name not in desired_xattrs:
                    with contextlib.suppress(OSError):
                        os.removexattr(target, name, follow_symlinks=False)
            for name, encoded in desired_xattrs.items():
                os.setxattr(target, name, decode_bytes(encoded), follow_symlinks=False)
        if operation.get("result_sha256"):
            if not stat.S_ISREG(os.lstat(target).st_mode) or _file_hash(os.fsencode(target)) != operation["result_sha256"]:
                raise SnapshotError(f"post-application content hash mismatch: {operation['path']}")
    if "manifest" in bundle and canonical_tree(destination) != bundle["manifest"]:
        raise SnapshotError("post-application canonical manifest mismatch")


def _policy_match(path: bytes, patterns: Sequence[bytes | str]) -> bool:
    return any(fnmatch.fnmatchcase(path, os_path_bytes(pattern)) for pattern in patterns)


def _xattrs(path: bytes) -> dict[str, str] | None:
    try:
        names = os.listxattr(path, follow_symlinks=False)
    except (OSError, AttributeError):
        return {}
    result: dict[str, str] = {}
    for name in sorted(names):
        try:
            result[os.fsdecode(name)] = encode_bytes(os.getxattr(path, name, follow_symlinks=False))
        except OSError:
            result[os.fsdecode(name)] = encode_bytes(b"")
    return result


def _entry_metadata(path: bytes, relative: bytes, info: os.stat_result, hard_links: dict[tuple[int, int], str],
                    cache: HashCache | None = None, snapshot_identity: str | None = None,
                    immutable: bool = False) -> dict[str, Any]:
    mode = stat.S_IMODE(info.st_mode)
    kind = (
        "directory" if stat.S_ISDIR(info.st_mode) else
        "regular" if stat.S_ISREG(info.st_mode) else
        "symlink" if stat.S_ISLNK(info.st_mode) else
        "fifo" if stat.S_ISFIFO(info.st_mode) else
        "socket" if stat.S_ISSOCK(info.st_mode) else
        "device" if stat.S_ISCHR(info.st_mode) or stat.S_ISBLK(info.st_mode) else None
    )
    if kind is None:
        raise SnapshotError(f"unsupported filesystem object: {os.fsdecode(relative)}")
    identity = None
    if kind == "regular" and info.st_nlink > 1:
        key = (info.st_dev, info.st_ino)
        identity = hard_links.setdefault(key, str(len(hard_links) + 1))
    entry: dict[str, Any] = {
        "path": encode_path(relative), "type": kind, "mode": mode,
        "uid": info.st_uid, "gid": info.st_gid, "mtime_ns": info.st_mtime_ns,
        "xattrs": _xattrs(path), "hard_link_id": identity,
    }
    if kind == "regular":
        encoded_path = entry["path"]
        cache_metadata = {key: entry[key] for key in ("type", "mode", "uid", "gid", "mtime_ns", "xattrs", "hard_link_id")}
        cache_metadata["size"] = info.st_size
        digest_value = cache.get(snapshot_identity, encoded_path, cache_metadata, immutable=True) if cache and snapshot_identity else None
        if digest_value is None:
            digest = hashlib.sha256()
            with open(path, "rb", buffering=0) as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            digest_value = digest.hexdigest()
            if cache and snapshot_identity:
                cache.put(snapshot_identity, encoded_path, cache_metadata, digest_value, immutable=immutable)
        entry.update(size=info.st_size, sha256=digest_value)
    elif kind == "symlink":
        entry["target"] = encode_bytes(os.readlink(path))
    elif kind == "device":
        entry.update(major=os.major(info.st_rdev), minor=os.minor(info.st_rdev))
    return entry


def canonical_tree(root: bytes | str, exclusions: Sequence[bytes | str] = (), *,
                   cache: HashCache | None = None, snapshot_identity: str | None = None,
                   immutable: bool = False) -> dict[str, Any]:
    """Return a deterministic manifest without following symbolic links."""
    root_bytes = os_path_bytes(root)
    entries: list[dict[str, Any]] = []
    hard_links: dict[tuple[int, int], str] = {}

    def visit(directory: bytes, relative: bytes = b"") -> None:
        try:
            children = sorted(os.scandir(directory), key=lambda item: os.fsencode(item.name))
        except OSError as error:
            raise SnapshotError(f"cannot traverse {os.fsdecode(directory)}") from error
        for child in children:
            name = os.fsencode(child.name)
            child_relative = name if not relative else relative + b"/" + name
            if _policy_match(child_relative, exclusions):
                continue
            child_path = os.path.join(directory, name)
            try:
                info = os.lstat(child_path)
                entry = _entry_metadata(child_path, child_relative, info, hard_links, cache, snapshot_identity, immutable)
            except OSError as error:
                raise SnapshotError(f"cannot inspect {os.fsdecode(child_relative)}") from error
            entries.append(entry)
            if entry["type"] == "directory":
                visit(child_path, child_relative)

    visit(root_bytes)
    entries.sort(key=lambda item: item["path"])
    # Use the group's first canonical path rather than traversal order as the
    # identity, so unrelated entries cannot renumber hard-link groups.
    first_paths: dict[str, str] = {}
    for entry in entries:
        if entry["hard_link_id"] is not None:
            first_paths.setdefault(entry["hard_link_id"], entry["path"])
    for entry in entries:
        if entry["hard_link_id"] is not None:
            entry["hard_link_id"] = first_paths[entry["hard_link_id"]]
    return {"schema": SCHEMAS["canonical-tree"], "version": SCHEMA_VERSION, "entries": entries}


def _entry_map(document: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    validate_document(document, "canonical-tree")
    return {entry["path"]: entry for entry in document["entries"]}


def _content(path: bytes) -> bytes:
    with open(path, "rb") as stream:
        return stream.read()


def compare_trees(baseline_root: bytes | str, observation_root: bytes | str, threshold: int = 1024 * 1024,
                  exclusions: Sequence[bytes | str] = (), redactions: Sequence[bytes | str] = (), *,
                  baseline_identity: str | None = None, observation_identity: str | None = None,
                  cache: HashCache | None = None, immutable: bool = False) -> dict[str, Any]:
    """Compare two trees; all file bytes are hashed, but emitted payloads are bounded."""
    before = canonical_tree(baseline_root, exclusions, cache=cache, snapshot_identity=baseline_identity, immutable=immutable)
    after = canonical_tree(observation_root, exclusions, cache=cache, snapshot_identity=observation_identity, immutable=immutable)
    old = _entry_map(before)
    new = _entry_map(after)
    changes: list[dict[str, Any]] = []
    for path in sorted(set(old) | set(new)):
        left, right = old.get(path), new.get(path)
        if left is None or right is None:
            change = {"path": path, "classification": "added" if left is None else "removed",
                      "old": left, "new": right, "reasons": []}
        elif left["type"] != right["type"]:
            change = {"path": path, "classification": "type-changed", "old": left, "new": right, "reasons": ["type"]}
        else:
            reasons = [field for field in ("mode", "uid", "gid", "mtime_ns", "xattrs", "hard_link_id") if left[field] != right[field]]
            classification = "unchanged"
            if left["type"] == "regular" and left["sha256"] != right["sha256"]:
                classification = "content-modified"
                reasons.append("content")
            elif left["type"] == "symlink" and left["target"] != right["target"]:
                classification = "link-target-modified"
                reasons.append("target")
            elif reasons:
                classification = "metadata-modified"
            change = {"path": path, "classification": classification, "old": left, "new": right, "reasons": reasons}
        if change["classification"] == "content-modified":
            left_size, right_size = left["size"], right["size"]
            if left_size <= threshold and right_size <= threshold and not _policy_match(decode_path(path), redactions):
                payload = _content(os.path.join(os_path_bytes(observation_root), decode_path(path)))
                change["content"] = {"encoding": "base64", "data": encode_bytes(payload)}
            elif _policy_match(decode_path(path), redactions):
                change["reasons"].append("content-redacted")
            else:
                change["reasons"].append("content-diff-omitted")
        elif change["classification"] in {"added", "type-changed"} and right and right["type"] == "regular":
            if right["size"] <= threshold and not _policy_match(decode_path(path), redactions):
                payload = _content(os.path.join(os_path_bytes(observation_root), decode_path(path)))
                change["content"] = {"encoding": "base64", "data": encode_bytes(payload)}
            else:
                change["reasons"].append("content-redacted" if _policy_match(decode_path(path), redactions) else "content-diff-omitted")
        if change["classification"] != "unchanged":
            changes.append(change)
    metadata = {"excluded": sorted(encode_path(os_path_bytes(pattern)) for pattern in exclusions),
                "redacted": sorted(encode_path(os_path_bytes(pattern)) for pattern in redactions),
                "baseline_manifest": before, "observed_manifest": after}
    return {"schema": SCHEMAS["drift-report"], "version": SCHEMA_VERSION,
            "baseline_snapshot": "", "observation_snapshot": "",
            "status": "drift" if changes else "clean", "changes": changes, "metadata": metadata}


def human_report(report: Mapping[str, Any]) -> str:
    """Render a stable, payload-free operator report."""
    validate_document(report, "drift-report")
    lines = [f"Filesystem snapshot report: {report['status']}",
             f"Baseline: {report['baseline_snapshot'] or '(unspecified)'}",
             f"Observation: {report['observation_snapshot'] or '(unspecified)'}"]
    for change in report["changes"]:
        path = os.fsdecode(decode_path(change["path"]))
        reasons = ", ".join(change.get("reasons", [])) or "none"
        lines.append(f"{change['classification']}: {path} ({reasons})")
    return "\n".join(lines) + "\n"


def write_reports(report: Mapping[str, Any], json_path: str | bytes | Path,
                  text_path: str | bytes | Path, *, mode: int = 0o640,
                  uid: int | None = None, gid: int | None = None) -> None:
    validate_document(report, "drift-report")
    atomic_write(json_path, canonical_json(report), mode=mode, uid=uid, gid=gid)
    atomic_write(text_path, human_report(report).encode("utf-8"), mode=mode, uid=uid, gid=gid)


def _main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "status", "baseline", "observe", "report", "promote", "retain", "export", "deploy"))
    parser.add_argument("kind", choices=tuple(SCHEMAS), nargs="?")
    parser.add_argument("input", type=argparse.FileType("rb"), nargs="?", default=sys.stdin.buffer)
    parser.add_argument("--source")
    parser.add_argument("--snapshot-root")
    parser.add_argument("--state-dir")
    parser.add_argument("--snapshot-id")
    parser.add_argument("--count", type=int)
    parser.add_argument("--age", type=int)
    parser.add_argument("--threshold", type=int, default=1024 * 1024)
    parser.add_argument("--exclude", action="append", default=[])
    parser.add_argument("--redact", action="append", default=[])
    parser.add_argument("--cache-dir")
    parser.add_argument("--report-json")
    parser.add_argument("--report-text")
    parser.add_argument("--mode", type=lambda value: int(value, 8), default=0o640)
    parser.add_argument("--uid", type=int)
    parser.add_argument("--gid", type=int)
    parser.add_argument("--destination")
    parser.add_argument("--bundle-output")
    parser.add_argument("--payload-dir")
    args = parser.parse_args(argv)
    try:
        if args.command == "export":
            report = json.load(args.input)
            bundle = export_bundle(report, payload_dir=args.payload_dir)
            data = canonical_json(bundle)
            if args.bundle_output:
                atomic_write(args.bundle_output, data, mode=args.mode, uid=args.uid, gid=args.gid)
            else:
                sys.stdout.buffer.write(data)
            return status_for(bundle)[0]
        if args.command == "deploy":
            if not args.destination:
                parser.error("deploy requires --destination")
            bundle = json.load(args.input)
            deploy_bundle(bundle, args.destination, payload_dir=args.payload_dir)
            print(canonical_json({"status": "deployed"}).decode("ascii"), end="")
            return 0
        if args.command in {"baseline", "observe", "report", "promote", "retain"}:
            if not args.source or not args.snapshot_root:
                parser.error("lifecycle commands require --source and --snapshot-root")
            manager = SnapshotManager(args.source, args.snapshot_root, args.state_dir)
            if args.command == "baseline":
                result = manager.baseline()
            elif args.command == "observe":
                result = manager.observe()
            elif args.command == "report":
                if not args.snapshot_id:
                    parser.error("report requires --snapshot-id")
                snapshot_id = manager.latest_observation() if args.snapshot_id == "latest" else args.snapshot_id
                result = manager.report(
                    snapshot_id, threshold=args.threshold,
                    exclusions=args.exclude, redactions=args.redact,
                    cache=HashCache(args.cache_dir) if args.cache_dir else None,
                )
                if args.report_json and args.report_text:
                    write_reports(result, args.report_json, args.report_text,
                                  mode=args.mode, uid=args.uid, gid=args.gid)
                elif args.report_json or args.report_text:
                    parser.error("report requires both --report-json and --report-text")
            elif args.command == "promote":
                if not args.snapshot_id:
                    parser.error("promote requires --snapshot-id")
                result = manager.promote(args.snapshot_id)
            else:
                result = {"removed": manager.retain(args.count, args.age)}
            print(canonical_json(result).decode("ascii"), end="")
            if args.command == "report":
                return EXIT_STATUS[result["status"]][0]
            return 0
        if not args.kind:
            parser.error("validate and status require a document kind")
        document = json.load(args.input)
        validate_document(document, args.kind)
        if args.command == "status":
            code, reason = status_for(document)
            print(json.dumps({"status": code, "reason": reason}, sort_keys=True))
            return code
        return 0
    except SnapshotError as error:
        print(json.dumps({"status": EXIT_STATUS["operational-error"][0], "reason": EXIT_STATUS["operational-error"][1], "error": str(error)}, sort_keys=True), file=sys.stderr)
        return EXIT_STATUS["operational-error"][0]
    except (OSError, ValueError, SchemaError, json.JSONDecodeError) as error:
        print(json.dumps({"status": EXIT_STATUS["validation-error"][0], "reason": "validation-error", "error": str(error)}, sort_keys=True), file=sys.stderr)
        return EXIT_STATUS["validation-error"][0]


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
