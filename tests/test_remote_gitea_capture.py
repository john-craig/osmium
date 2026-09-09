import json
import tempfile
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))
from tools.remote_gitea_capture import (  # noqa: E402
    CaptureError,
    SCHEMA,
    SCHEMA_VERSION,
    canonical_json,
    convert_capture,
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


if __name__ == "__main__":
    unittest.main()
