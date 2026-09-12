import json
import tempfile
import sys
import unittest
from unittest.mock import patch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))
from tools.remote_gitea_capture import (  # noqa: E402
    CaptureError,
    SCHEMA,
    SCHEMA_VERSION,
    canonical_json,
    convert_capture,
    compare_repository_drift,
    convert_drift,
    capture as remote_capture,
    normalize_capture,
    local_probe,
    render_nix,
)


def capture(**overrides):
    value = {
        "schema": SCHEMA,
        "version": SCHEMA_VERSION,
        "adapter": {"name": "nixos-gitea", "version": 1, "probes": ["identities"]},
        "source": {"host": "redacted", "origin": "observed"},
        "scope": "gitea",
        "service": {"stateDir": "/var/lib/gitea", "settings": {"service": {"DISABLE_REGISTRATION": False}}},
        "users": [{"username": "alice", "email": "alice@example.com"}],
        "organizations": [{"name": "alice-org", "owner": "alice", "visibility": "private"}],
        "repositories": [],
        "persistence": [{"path": "/var/lib/gitea", "origin": "observed"}],
        "probes": [{"name": "identities", "status": "ok", "origin": "observed"}],
        "findings": [],
        "complete": True,
    }
    value.update(overrides)
    return value


class RemoteCaptureContractTests(unittest.TestCase):
    def test_normalization_is_order_independent_and_secret_free(self):
        first = capture(users=[{"username": "alice", "email": "alice@example.com", "password": "never"}, {"username": "bob", "email": "bob@example.com"}])
        second = capture(users=list(reversed(first["users"])))
        self.assertEqual(canonical_json(normalize_capture(first)), canonical_json(normalize_capture(second)))
        self.assertNotIn("never", canonical_json(normalize_capture(first)))

    def test_unknown_version_and_unsafe_paths_fail_closed(self):
        with self.assertRaises(CaptureError):
            normalize_capture(capture(version=2))
        with self.assertRaises(CaptureError):
            normalize_capture(capture(persistence=[{"path": "/tmp/secret"}]))

    def test_conversion_surfaces_secrets_and_unsupported_state(self):
        value = capture(
            users=capture()["users"] + [{"username": "admin", "admin": True}],
            unsupported=["repositories"],
        )
        candidate = convert_capture(value)
        text = canonical_json(candidate)
        self.assertFalse(candidate["complete"])
        self.assertIn("unresolved-secret-file", text)
        self.assertIn("administrator-account", text)
        self.assertIn("unsupported-state", text)
        self.assertNotIn("never", render_nix(candidate))

    def test_candidate_is_nix_shaped_and_deterministic(self):
        candidate = convert_capture(capture(), {"alice": "/run/alice-password"})
        self.assertTrue(candidate["complete"])
        rendered = render_nix(candidate)
        self.assertEqual(rendered, render_nix(json.loads(json.dumps(candidate))))
        self.assertIn("user_alice", rendered)
        self.assertIn("alice-password", rendered)

    def test_local_probe_vocabulary_fails_closed_for_identity_state(self):
        self.assertEqual(local_probe("identities")["status"], "unsupported")
        self.assertEqual(local_probe("persistence")["paths"][0]["path"], "/var/lib/gitea")

    def test_partial_and_unsupported_observations_are_not_complete(self):
        value = capture(
            complete=True,
            probes=[{"name": "identities", "status": "unsupported", "origin": "observed"}],
            findings=[{"code": "unsupported-probe", "severity": "required", "probe": "identities"}],
        )
        normalized = normalize_capture(value)
        self.assertFalse(normalized["complete"])
        self.assertFalse(convert_capture(normalized)["activation_ready"])

    def test_ambiguous_and_unsafe_records_are_stable_findings(self):
        candidate = convert_capture(
            capture(
                users=[{"username": "bad/name"}],
                organizations=[{"name": "team", "owner": "missing"}],
            )
        )
        codes = [finding["code"] for finding in candidate["findings"]]
        self.assertEqual(codes, ["ambiguous-owner", "unsafe-name"])
        self.assertFalse(candidate["complete"])

    def test_transport_failures_do_not_create_artifacts(self):
        from tools.remote_gitea_capture import SSHTransport

        with tempfile.TemporaryDirectory() as directory:
            command = Path(directory) / "ssh"
            command.write_text("#!/bin/sh\nexit 255\n", encoding="utf-8")
            command.chmod(0o755)
            with self.assertRaises(CaptureError):
                SSHTransport("unreachable", "capture", known_hosts="/dev/null", command=str(command)).run("platform")

    def test_repositories_normalize_independently_of_api_order(self):
        repositories = [
            {"owner_kind": "organization", "owner": "alice-org", "name": "docs", "has_wiki": True, "private": True},
            {"owner_kind": "user", "owner": "alice", "name": "app", "description": "A"},
        ]
        first = normalize_capture(capture(repositories=repositories))
        second = normalize_capture(capture(repositories=list(reversed(repositories))))
        self.assertEqual(canonical_json(first), canonical_json(second))
        self.assertEqual([item["name"] for item in first["repositories"]], ["docs", "app"])

    def test_repository_conversion_preserves_owner_and_metadata(self):
        candidate = convert_capture(capture(users=[], organizations=[], repositories=[
            {"owner_kind": "user", "owner": "alice", "name": "app", "description": "A", "private": True, "issues": True},
            {"owner_kind": "organization", "owner": "alice-org", "name": "docs", "wiki": True},
        ]))
        repositories = candidate["gitea"]["repositories"]
        self.assertEqual(repositories["repository_alice_app"]["owner"], {"user": "alice"})
        self.assertTrue(repositories["repository_alice_app"]["private"])
        self.assertEqual(repositories["repository_alice_org_docs"]["owner"], {"organization": "alice-org"})

    def test_drift_is_per_attribute_and_conversion_is_deterministic(self):
        declared = [{"owner_kind": "user", "owner": "alice", "name": "app", "description": "old", "private": False}]
        observed = [{"owner_kind": "user", "owner": "alice", "name": "app", "description": "new", "private": True}]
        report = compare_repository_drift(declared, observed)
        self.assertEqual([item["field"] for item in report["changes"]], ["description", "private"])
        first = convert_drift(report)
        second = convert_drift(json.loads(json.dumps(report)))
        self.assertEqual(canonical_json(first), canonical_json(second))
        self.assertEqual(first["gitea"]["repositories"]["repository_alice_app"]["description"], "new")

    def test_capture_carries_repository_scope_and_provenance(self):
        class Transport:
            host = "gitea.example"
            def run(self, probe, payload=None):
                if probe == "platform":
                    return {"platform": "nixos"}
                if probe == "service":
                    return {"status": "ok", "service": {"stateDir": "/var/lib/gitea", "paths": []}}
                if probe == "persistence":
                    return {"status": "ok", "paths": []}
                return {"status": "ok", "users": [], "organizations": [], "repositories": [{"owner_kind": "organization", "owner": "team", "name": "docs"}], "capabilities": {"repository_fields": ["description"]}}
        result = remote_capture(Transport(), scope="repositories")
        self.assertEqual(result["scope"], "repositories")
        self.assertEqual(result["repositories"][0]["owner"], "team")
        self.assertEqual(result["source"]["origin"], "observed")

    def test_drift_classifies_owner_kind_conflict(self):
        report = compare_repository_drift(
            [{"owner_kind": "user", "owner": "alice", "name": "app"}],
            [{"owner_kind": "organization", "owner": "alice", "name": "app"}],
        )
        self.assertEqual([item["classification"] for item in report["changes"]], ["owner-conflict"])
        self.assertFalse(report["complete"])

    def test_repository_content_and_sensitive_integrations_are_findings(self):
        candidate = convert_capture(capture(repositories=[{
            "owner_kind": "organization", "owner": "alice-org", "name": "docs",
            "contents": "secret git data", "webhooks": [{"secret": "never"}],
        }]))
        text = canonical_json(candidate)
        self.assertFalse(candidate["activation_ready"])
        self.assertIn("repository-content", text)
        self.assertIn("sensitive-or-unmanaged-integrations", text)
        self.assertNotIn("secret git data", text)
        self.assertNotIn("never", text)

    def test_local_probe_paginates_repositories_and_accepts_search_shape(self):
        class Response:
            def __init__(self, payload):
                self.payload = payload
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
            def read(self):
                return json.dumps(self.payload).encode()
        repos_page_one = [{"owner": {"login": "alice"}, "name": f"repo-{index}", "id": index} for index in range(50)]
        pages = {"admin/users": [[]], "admin/orgs": [[]], "repos/search": [repos_page_one, {"data": [{"owner": {"login": "team", "type": "Organization"}, "name": "two", "id": 1}]}]}
        def urlopen(request, timeout):
            endpoint = request.full_url.split("/api/v1/", 1)[1].split("?", 1)[0]
            payload = pages[endpoint].pop(0)
            return Response(payload)
        import os
        with tempfile.TemporaryDirectory() as directory:
            token_path = Path(directory) / "token"
            token_path.write_text("runtime-token", encoding="utf-8")
            with patch.dict(os.environ, {"OSMIUM_GITEA_API_TOKEN_FILE": str(token_path), "OSMIUM_GITEA_API_URL": "http://gitea/api/v1"}), patch("tools.remote_gitea_capture.urllib.request.urlopen", side_effect=urlopen):
                result = local_probe("identities")
        self.assertEqual(result["status"], "ok")
        self.assertEqual(len(result["repositories"]), 51)
        self.assertEqual(result["repositories"][-1]["owner_kind"], "organization")
        self.assertEqual(result["capabilities"]["endpoint"], "owner/repos")


if __name__ == "__main__":
    unittest.main()
