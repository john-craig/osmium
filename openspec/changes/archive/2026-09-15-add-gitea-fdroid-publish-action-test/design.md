## Context

The existing checks boot Gitea and F-Droid independently. Gitea already
supports declarative users, repositories, and protected credentials, while the
F-Droid module consumes declared APK paths and atomically generates a signed
repository. Neither module currently owns a cross-service artifact transport,
and this change must remain a test addition rather than introduce a production
upload API.

The F-Droid generator currently runs at boot and expects every declared
artifact path to be readable. The cross-service check therefore needs a
test-specific ordering mechanism that leaves the destination declared while
allowing the Actions run to create its bytes after boot.

## Goals / Non-Goals

**Goals:**

- Exercise actual Gitea Actions scheduling and runner execution, not a shell
  script invoked directly by the test driver.
- Keep service topology, source content, credentials, trust roots, and startup
  ordering in NixOS test configuration.
- Verify both APK application signing and F-Droid repository index signing.
- Keep the check hermetic after its Nix inputs are realized.
- Give failures observable checkpoints for runner registration, action status,
  transfer, repository generation, and HTTP probing.

**Non-Goals:**

- Add a production F-Droid upload service or general artifact promotion API.
- Add Gitea Actions options to `services.osmium.gitea`.
- Model CI repository contents as new Osmium declarative attributes.
- Test Android application functionality, multiple package versions, rotation,
  or production secret distribution.
- Reuse the isolated test credential outside this check.

## Decisions

### Use one Gitea/runner guest and one F-Droid guest

The NixOS test will define `gitea` and `fdroid` nodes with deterministic names
and addresses on the test network. Gitea and the nixpkgs
`services.gitea-actions-runner` instance run together so the runner can use a
host execution label without adding a third VM or a container runtime. The
workflow publishes to `fdroid` by guest hostname.

A single combined VM was rejected because it would not validate remote
authentication, host trust, or cross-service networking. A third runner VM was
rejected as extra cost that does not improve the required service boundary.

### Use a hermetic host-execution workflow

The runner label will expose only the pinned packages required by the workflow:
shell utilities, Git, OpenSSH, JDK, and the composed Android SDK/build tools.
The repository workflow will use shell commands directly to compile a minimal
no-code Android package with `aapt2`, sign it with `apksigner`, verify it, and
publish it. It will not invoke marketplace actions such as `actions/checkout`,
which would add external network and action-version dependencies.

The job receives the checked-out Gitea repository through the runner's native
workspace behavior. Building an APK as a Nix derivation outside the Actions run
was rejected because it would not prove that CI performed the build.

### Seed repository content only after runner and credentials are ready

The Android manifest and `.gitea/workflows/publish.yaml` will be immutable test
fixtures. A declarative oneshot unit in the Gitea guest will create the initial
Git commit and push it to the already declared repository only after Gitea,
runner registration, signing preparation, and publication preparation are
complete. That push is the sole workflow trigger.

The test driver may wait and inspect, but it will not create repositories,
install credentials, copy the APK, or manually dispatch the workflow. This
separates declarative setup from acceptance assertions and avoids a race in
which the push precedes runner registration.

### Provision test credentials before the trigger

The test will use a dedicated test-only SSH publication key pair and a pinned
F-Droid SSH host key as Nix fixtures. The F-Droid guest authorizes the public
key for a publication account limited to its incoming directory; the runner
receives the private key and known-hosts entry as mode `0400` files readable by
its service user. Test-only systemd preparation units generate the APK signing
keystore on the Gitea guest and the repository signing keystore on the F-Droid
guest at runtime, before the source push and repository generation respectively.

The workflow refers to protected file paths rather than embedding private bytes
in workflow YAML or command arguments. Using password authentication or
`StrictHostKeyChecking=no` was rejected because it would not validate
non-interactive trust setup. Production-grade secret transport is out of scope;
the fixed SSH fixture is isolated to the test closure and must be labelled as
non-production material.

### Stage into the F-Droid module's declared artifact path

The F-Droid declaration will identify the expected package, version, and an
absolute incoming APK path. A test-specific systemd override will make the
generation unit retry while that file is absent. The SSH publication account
can write the incoming directory but cannot write the served repository tree or
signing files. Once the signed APK arrives atomically, the normal Osmium F-Droid
generator consumes that declared path, generates signed indexes, and starts the
read-only HTTP server.

Directly copying into the served `repo/` directory and invoking `fdroid update`
from the workflow was rejected because it would bypass the module's declared
artifact contract and generation lifecycle. Adding an upload endpoint was
rejected as production scope unsupported by this test change.

### Observe completion through Gitea and F-Droid interfaces

The test driver will poll Gitea's API for the triggered commit's workflow run
and require a successful terminal conclusion. It will then poll the F-Droid
readiness marker and HTTP endpoint. `curl` will retrieve the signed index and
APK from the F-Droid guest; index inspection will assert package and version,
checksum comparison will link the served bytes to the uploaded artifact, and
`apksigner verify --print-certs` will assert the expected certificate identity.

Checking only for an APK file was rejected because it could pass despite a
failed Actions run or an index that never exposed the artifact.

## Risks / Trade-offs

- [Gitea Actions API fields or runner registration commands vary with the
  pinned Gitea version] -> Use the pinned nixpkgs packages and assert explicit
  registration and terminal-run states with diagnostics on timeout.
- [Host execution exposes more of the guest than a container job] -> Restrict
  the label's package set and use a disposable test-only MicroVM; do not present
  this as a production runner hardening pattern.
- [F-Droid generation begins before publication] -> Add a test-only retry and
  dependency override while preserving the normal generator and declared
  artifact path.
- [The fixed SSH fixture is visible in the test closure] -> Mark it test-only,
  scope its authorization to the disposable publication account and incoming
  directory, and never reuse it in examples or production configuration.
- [Android SDK realization makes the check large or license-sensitive] -> Reuse
  the existing composed SDK pattern and accepted-license test import, pin one
  platform/build-tools version, and build the smallest no-code APK possible.
- [Action logs accidentally reveal protected data] -> Pass only file paths,
  disable shell tracing around credential use, and scan the completed job log
  for fixture private-key and keystore-password markers.

## Migration Plan

Add the test file, immutable fixtures, and flake check without changing enabled
services or existing checks. Rollback removes only those test artifacts and the
flake check entry; no production state or configuration migration is required.
