import json
import base64
import os
import stat
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))
from tools.filesystem_snapshot import (  # noqa: E402
    EXIT_STATUS,
    SCHEMA_VERSION,
    SCHEMAS,
    SchemaError,
    canonical_json,
    decode_path,
    encode_path,
    SnapshotError,
    SnapshotManager,
    HashCache,
    human_report,
    write_reports,
    canonical_tree,
    compare_trees,
    deploy_bundle,
    decode_bytes,
    encode_bytes,
    export_bundle,
    validate_bundle,
    validate_document,
)


def tree(*entries):
    return {"schema": SCHEMAS["canonical-tree"], "version": SCHEMA_VERSION, "entries": sorted(entries, key=lambda item: item["path"])}


def regular(path, sha="0" * 64):
    return {"path": encode_path(path), "type": "regular", "mode": 0o644, "uid": 1000, "gid": 1000, "mtime_ns": 1, "xattrs": {}, "hard_link_id": None, "size": 2, "sha256": sha}


class FilesystemSnapshotContractTests(unittest.TestCase):
    def test_byte_safe_paths_and_deterministic_tree(self):
        path = b"etc/a\xff.conf"
        self.assertEqual(decode_path(encode_path(path)), path)
        document = tree(regular(path), regular(b"z"))
        self.assertEqual(canonical_json(document), canonical_json(json.loads(canonical_json(document))))
        validate_document(document, "canonical-tree")
        self.assertNotIn("inode", canonical_json(document).decode())

    def test_representative_documents_validate(self):
        validate_document(tree(regular("etc/app")), "canonical-tree")
        validate_document({"schema": SCHEMAS["snapshot-metadata"], "version": 1, "snapshot_id": "s1", "source_id": "src", "role": "baseline", "created_at": "2026-01-01T00:00:00Z", "read_only": True, "complete": True}, "snapshot-metadata")
        validate_document({"schema": SCHEMAS["drift-report"], "version": 1, "baseline_snapshot": "s1", "observation_snapshot": "s2", "status": "drift", "changes": [{"path": encode_path("etc/app")}], "metadata": {}}, "drift-report")
        validate_document({"schema": SCHEMAS["reconstruction-bundle"], "version": 1, "baseline_snapshot": "s1", "observed_snapshot": "s2", "complete": True, "operations": [], "incomplete": []}, "reconstruction-bundle")

    def test_unknown_versions_and_malformed_records_fail(self):
        document = tree(regular("file"))
        document["version"] = 2
        with self.assertRaises(SchemaError):
            validate_document(document, "canonical-tree")
        document = tree(regular("file"))
        document["entries"][0]["path"] = "not-a-path"
        with self.assertRaises(SchemaError):
            validate_document(document, "canonical-tree")
        malformed = {"schema": SCHEMAS["reconstruction-bundle"], "version": 1, "baseline_snapshot": "s1", "observed_snapshot": "s2", "complete": True, "operations": [{"path": encode_path("file")}], "incomplete": []}
        with self.assertRaises(SchemaError):
            validate_document(malformed, "reconstruction-bundle")

    def test_symlink_targets_are_arbitrary_bytes_and_not_paths(self):
        entry = {"path": encode_path("link"), "type": "symlink", "mode": 0o777,
                 "uid": 0, "gid": 0, "mtime_ns": 1, "xattrs": {},
                 "hard_link_id": None, "target": encode_bytes(b"../../outside\xff")}
        validate_document(tree(entry), "canonical-tree")

    def test_command_status_contract(self):
        for status in ("clean", "drift", "operational-error"):
            report = {"schema": SCHEMAS["drift-report"], "version": 1, "baseline_snapshot": "s1", "observation_snapshot": "s2", "status": status, "changes": [], "metadata": {}}
            process = subprocess.run([sys.executable, "tools/filesystem_snapshot.py", "status", "drift-report"], input=canonical_json(report), capture_output=True)
            self.assertEqual(process.returncode, EXIT_STATUS[status][0])
            self.assertIn(EXIT_STATUS[status][1].encode(), process.stdout)
        bundle = {"schema": SCHEMAS["reconstruction-bundle"], "version": 1, "baseline_snapshot": "s1", "observed_snapshot": "s2", "complete": False, "operations": [], "incomplete": [{"path": encode_path("file"), "reason": "content-diff-omitted"}]}
        process = subprocess.run([sys.executable, "tools/filesystem_snapshot.py", "status", "reconstruction-bundle"], input=canonical_json(bundle), capture_output=True)
        self.assertEqual(process.returncode, EXIT_STATUS["incomplete-export"][0])
        self.assertIn(EXIT_STATUS["incomplete-export"][1].encode(), process.stdout)
        process = subprocess.run([sys.executable, "tools/filesystem_snapshot.py", "status", "canonical-tree"], input=b"{}", capture_output=True)
        self.assertEqual(process.returncode, EXIT_STATUS["validation-error"][0])


class FakeBtrfs:
    def __init__(self, source):
        self.source = source
        self.identities = {os.fsencode(source): ("source-uuid", "-")}
        self.deleted = []
        self.fail_snapshot = False
        self.read_only = True

    def __call__(self, argv):
        command = [os.fsdecode(item) for item in argv]
        if command[:3] == ["btrfs", "subvolume", "show"]:
            identity, parent = self.identities[argv[-1]]
            output = f"UUID: {identity}\nParent UUID: {parent}\n".encode()
            return subprocess.CompletedProcess(argv, 0, output, b"")
        if command[:3] == ["btrfs", "property", "get"]:
            value = b"ro=true\n" if self.read_only else b"ro=false\n"
            return subprocess.CompletedProcess(argv, 0, value, b"")
        if command[:4] == ["btrfs", "subvolume", "snapshot", "-r"]:
            if self.fail_snapshot:
                return subprocess.CompletedProcess(argv, 1, b"", b"failed")
            destination = Path(os.fsdecode(argv[-1]))
            destination.mkdir()
            identity = f"snapshot-{len(self.identities)}"
            self.identities[os.fsencode(destination)] = (identity, "source-uuid")
            return subprocess.CompletedProcess(argv, 0, b"", b"")
        if command[:4] == ["btrfs", "subvolume", "delete", "--"]:
            self.deleted.append(argv[-1])
            self.identities.pop(argv[-1], None)
            Path(os.fsdecode(argv[-1])).rmdir()
            return subprocess.CompletedProcess(argv, 0, b"", b"")
        raise AssertionError(command)


class SnapshotLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.source = self.root / "source"
        self.snapshot_root = self.root / "snapshots"
        self.state = self.root / "state"
        self.source.mkdir()
        (self.source / "unchanged").write_text("source")
        self.runner = FakeBtrfs(self.source)
        self.manager = SnapshotManager(self.source, self.snapshot_root, self.state, self.runner)

    def tearDown(self):
        self.directory.cleanup()

    def test_operations_are_serialized_and_promotion_is_explicit(self):
        baseline = self.manager.baseline()
        observation = self.manager.observe()
        state = json.loads((self.state / "state.json").read_text())
        self.assertEqual(state["current_baseline"], baseline["metadata"]["snapshot_id"])
        self.assertNotEqual(baseline["metadata"]["snapshot_id"], observation["metadata"]["snapshot_id"])
        self.assertEqual(self.manager.promote(observation["metadata"]["snapshot_id"])["metadata"]["role"], "baseline")
        self.assertEqual(json.loads((self.state / "state.json").read_text())["current_baseline"], observation["metadata"]["snapshot_id"])
        self.assertEqual((self.source / "unchanged").read_text(), "source")

    def test_validation_failures_do_not_look_like_deletions(self):
        baseline = self.manager.baseline()
        observation = self.manager.observe()
        observation["metadata"]["source_id"] = "other-source"
        with self.assertRaises(SnapshotError):
            self.manager._validate_record(observation)
        self.assertTrue(Path(baseline["path"]).exists())
        self.assertTrue(Path(observation["path"]).exists())
        self.runner.read_only = False
        with self.assertRaises(SnapshotError):
            self.manager._validate_record(baseline)
        Path(observation["path"]).rmdir()
        with self.assertRaises(SnapshotError):
            self.manager._validate_record(observation)

    def test_interrupted_snapshot_has_no_completion_record(self):
        self.runner.fail_snapshot = True
        with self.assertRaises(SnapshotError):
            self.manager.baseline()
        self.assertFalse((self.state / "state.json").exists())
        self.assertEqual(list((self.snapshot_root).glob("*")), [])

    def test_retention_protects_baseline_and_active_references(self):
        baseline = self.manager.baseline()
        first = self.manager.observe()
        second = self.manager.observe()
        state = json.loads((self.state / "state.json").read_text())
        state["active_references"] = [second["metadata"]["snapshot_id"]]
        (self.state / "state.json").write_text(json.dumps(state))
        removed = self.manager.retain(count=1)
        self.assertEqual(removed, [first["metadata"]["snapshot_id"]])
        self.assertTrue(Path(baseline["path"]).exists())
        self.assertTrue(Path(second["path"]).exists())

    def test_age_retention_removes_only_old_unprotected_snapshots(self):
        baseline = self.manager.baseline()
        observation = self.manager.observe()
        removed = self.manager.retain(age=0, now=time.time() + 1)
        self.assertEqual(removed, [observation["metadata"]["snapshot_id"]])
        self.assertTrue(Path(baseline["path"]).exists())


class FilesystemComparisonTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.before = self.root / "before"
        self.after = self.root / "after"
        self.before.mkdir()
        self.after.mkdir()

    def tearDown(self):
        self.directory.cleanup()

    def test_traversal_is_byte_safe_non_following_and_covers_object_types(self):
        (self.before / "dir").mkdir()
        (self.before / "dir" / "file").write_bytes(b"bytes\xff")
        os.symlink(b"../../outside\xff", self.before / "dir" / "link")
        os.mkfifo(self.before / "pipe")
        socket_path = self.before / "socket"
        sock = __import__("socket").socket(__import__("socket").AF_UNIX)
        sock.bind(os.fsencode(socket_path))
        try:
            document = canonical_tree(self.before)
        finally:
            sock.close()
        types = {decode_path(entry["path"]): entry["type"] for entry in document["entries"]}
        self.assertEqual(types[b"dir/file"], "regular")
        self.assertEqual(types[b"dir/link"], "symlink")
        self.assertEqual(types[b"pipe"], "fifo")
        self.assertEqual(types[b"socket"], "socket")
        self.assertEqual(decode_bytes(next(item for item in document["entries"] if item["type"] == "symlink")["target"]), b"../../outside\xff")
        validate_document(document, "canonical-tree")

    def test_device_nodes_are_described_when_permitted(self):
        path = self.before / "null"
        try:
            os.mknod(path, stat.S_IFCHR | 0o666, os.makedev(1, 3))
        except (PermissionError, AttributeError):
            self.skipTest("device-node creation is unavailable")
        entry = next(item for item in canonical_tree(self.before)["entries"] if item["path"] == encode_path("null"))
        self.assertEqual((entry["type"], entry["major"], entry["minor"]), ("device", 1, 3))

    def test_classifies_all_supported_drift_kinds_and_hard_link_topology(self):
        (self.before / "same").write_bytes(b"same")
        (self.after / "same").write_bytes(b"same")
        (self.before / "content").write_bytes(b"old")
        (self.after / "content").write_bytes(b"new")
        (self.before / "metadata").write_bytes(b"meta")
        (self.after / "metadata").write_bytes(b"meta")
        os.chmod(self.after / "metadata", 0o600)
        (self.before / "removed").write_bytes(b"gone")
        (self.after / "added").write_bytes(b"new file")
        os.symlink(b"one", self.before / "link")
        os.symlink(b"two", self.after / "link")
        (self.before / "changed").write_bytes(b"object")
        (self.after / "changed").mkdir()
        (self.before / "hard-a").write_bytes(b"hard")
        os.link(self.before / "hard-a", self.before / "hard-b")
        (self.after / "hard-a").write_bytes(b"hard")
        (self.after / "hard-b").write_bytes(b"hard")
        for name in ("same", "content", "metadata", "link", "changed", "hard-a", "hard-b"):
            before = self.before / name
            after = self.after / name
            if before.is_symlink():
                before_stat = os.lstat(before)
            else:
                before_stat = before.stat()
            os.utime(after, ns=(before_stat.st_atime_ns, before_stat.st_mtime_ns), follow_symlinks=False)
        report = compare_trees(self.before, self.after)
        classifications = {decode_path(item["path"]): item["classification"] for item in report["changes"]}
        self.assertEqual(classifications, {b"added": "added", b"changed": "type-changed", b"content": "content-modified",
                                           b"hard-a": "metadata-modified", b"hard-b": "metadata-modified",
                                           b"link": "link-target-modified", b"metadata": "metadata-modified", b"removed": "removed"})
        self.assertNotEqual(next(item for item in report["changes"] if decode_path(item["path"]) == b"content")["old"]["sha256"],
                            next(item for item in report["changes"] if decode_path(item["path"]) == b"content")["new"]["sha256"])

    def test_payload_round_trip_is_bounded_and_redaction_has_no_bytes(self):
        (self.before / "small").write_bytes(b"old\x00\xff")
        (self.after / "small").write_bytes(b"new\x00\xfe")
        (self.before / "large").write_bytes(b"a" * 8)
        (self.after / "large").write_bytes(b"b" * 8)
        (self.before / "secret").write_bytes(b"old-secret")
        (self.after / "secret").write_bytes(b"new-secret")
        report = compare_trees(self.before, self.after, threshold=5, redactions=["secret"])
        by_path = {decode_path(item["path"]): item for item in report["changes"]}
        self.assertEqual(decode_bytes(by_path[b"small"]["content"]["data"]), b"new\x00\xfe")
        self.assertNotIn("content", by_path[b"large"])
        self.assertIn("content-diff-omitted", by_path[b"large"]["reasons"])
        self.assertNotIn("content", by_path[b"secret"])
        self.assertIn("content-redacted", by_path[b"secret"]["reasons"])
        self.assertNotIn(b"new-secret", canonical_json(report))
        validate_document(report, "drift-report")

    def test_oversized_metadata_change_has_equal_hashes_without_content_drift(self):
        (self.before / "large").write_bytes(b"x" * 8)
        (self.after / "large").write_bytes(b"x" * 8)
        before_stat = os.stat(self.before / "large")
        os.utime(self.after / "large", ns=(before_stat.st_atime_ns, before_stat.st_mtime_ns + 1))
        report = compare_trees(self.before, self.after, threshold=4)
        change = report["changes"][0]
        self.assertEqual(change["classification"], "metadata-modified")
        self.assertEqual(change["old"]["sha256"], change["new"]["sha256"])
        self.assertNotIn("content-diff-omitted", change["reasons"])

    def test_exclusions_prune_subtrees_and_record_policy(self):
        (self.before / "keep").write_bytes(b"same")
        (self.after / "keep").write_bytes(b"same")
        (self.before / "excluded").mkdir()
        (self.after / "excluded").mkdir()
        (self.before / "excluded" / "old").write_bytes(b"old")
        (self.after / "excluded" / "new").write_bytes(b"new")
        keep_stat = os.stat(self.before / "keep")
        os.utime(self.after / "keep", ns=(keep_stat.st_atime_ns, keep_stat.st_mtime_ns))
        report = compare_trees(self.before, self.after, exclusions=["excluded"])
        self.assertEqual(report["changes"], [])
        self.assertEqual(report["metadata"]["excluded"], [encode_path("excluded")])

    def test_reports_are_deterministic_and_written_restrictively(self):
        (self.before / "changed").write_bytes(b"old")
        (self.after / "changed").write_bytes(b"new")
        report = compare_trees(self.before, self.after)
        first = self.root / "first"
        second = self.root / "second"
        write_reports(report, first / "report.json", first / "report.txt", mode=0o600)
        write_reports(report, second / "report.json", second / "report.txt", mode=0o600)
        self.assertEqual((first / "report.json").read_bytes(), (second / "report.json").read_bytes())
        self.assertEqual((first / "report.txt").read_bytes(), (second / "report.txt").read_bytes())
        self.assertEqual(stat.S_IMODE((first / "report.json").stat().st_mode), 0o600)
        self.assertIn("content-modified: changed", human_report(report))

    def test_hash_cache_requires_immutable_input_and_invalidates_metadata(self):
        (self.before / "cached").write_bytes(b"same")
        cache = HashCache(self.root / "cache")
        first = canonical_tree(self.before, cache=cache, snapshot_identity="immutable-1", immutable=True)
        second = canonical_tree(self.before, cache=cache, snapshot_identity="immutable-1", immutable=True)
        self.assertEqual(first, second)
        entry = next(item for item in first["entries"] if decode_path(item["path"]) == b"cached")
        metadata = {key: entry[key] for key in ("type", "mode", "uid", "gid", "mtime_ns", "xattrs", "hard_link_id", "size")}
        self.assertEqual(cache.get("immutable-1", entry["path"], metadata, immutable=True), entry["sha256"])
        self.assertIsNone(cache.get("immutable-1", entry["path"], metadata, immutable=False))
        os.utime(self.before / "cached", ns=(entry["mtime_ns"], entry["mtime_ns"] + 1))
        changed = canonical_tree(self.before, cache=cache, snapshot_identity="immutable-1", immutable=True)
        changed_entry = next(item for item in changed["entries"] if decode_path(item["path"]) == b"cached")
        self.assertIsNone(cache.get("immutable-1", entry["path"], metadata, immutable=True))
        self.assertEqual(changed_entry["sha256"], entry["sha256"])


class ReconstructionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.before = self.root / "before"
        self.after = self.root / "after"
        self.before.mkdir()
        self.after.mkdir()
        (self.before / "same").write_bytes(b"same")
        (self.after / "same").write_bytes(b"same")
        (self.before / "changed").write_bytes(b"old")
        (self.after / "changed").write_bytes(b"new")
        (self.after / "added").write_bytes(b"added")
        (self.before / "removed").write_bytes(b"removed")
        os.symlink(b"changed", self.after / "link")

    def tearDown(self):
        self.directory.cleanup()

    def test_export_is_deterministic_and_content_addressed(self):
        report = compare_trees(self.before, self.after)
        first = export_bundle(report)
        second = export_bundle(json.loads(canonical_json(report)))
        self.assertEqual(canonical_json(first), canonical_json(second))
        self.assertTrue(first["complete"])
        self.assertEqual(len(first["payloads"]), 2)
        self.assertTrue(all(len(digest) == 64 for digest in first["payloads"]))

    def test_incomplete_bundle_fails_default_preflight_without_mutation(self):
        (self.before / "large").write_bytes(b"a" * 10)
        (self.after / "large").write_bytes(b"b" * 10)
        report = compare_trees(self.before, self.after, threshold=2)
        bundle = export_bundle(report)
        self.assertFalse(bundle["complete"])
        destination = self.root / "destination"
        destination.mkdir()
        (destination / "sentinel").write_text("untouched")
        with self.assertRaises(SchemaError):
            validate_bundle(bundle, destination)
        self.assertEqual((destination / "sentinel").read_text(), "untouched")

    def test_preflight_rejects_escape_before_mutation(self):
        report = compare_trees(self.before, self.after)
        bundle = export_bundle(report)
        bundle["operations"][0]["path"] = base64.urlsafe_b64encode(b"../escape").decode().rstrip("=")
        with self.assertRaises(SchemaError):
            deploy_bundle(bundle, self.root / "destination")
        self.assertFalse((self.root / "escape").exists())

    def test_complete_bundle_reconstructs_observed_manifest(self):
        report = compare_trees(self.before, self.after)
        bundle = export_bundle(report)
        destination = self.root / "destination"
        shutil.copytree(self.before, destination, symlinks=True, copy_function=shutil.copy2)
        deploy_bundle(bundle, destination)
        self.assertEqual(canonical_tree(destination), canonical_tree(self.after))

    def test_export_does_not_mutate_inputs_or_repository_state(self):
        marker = self.root / "nix-source-marker"
        marker.write_text("unchanged")
        before_state = canonical_tree(self.before)
        after_state = canonical_tree(self.after)
        report = compare_trees(self.before, self.after)
        export_bundle(report, payload_dir=self.root / "payloads")
        self.assertEqual(canonical_tree(self.before), before_state)
        self.assertEqual(canonical_tree(self.after), after_state)
        self.assertEqual(marker.read_text(), "unchanged")
        self.assertFalse((self.root / ".git").exists())


if __name__ == "__main__":
    unittest.main()
