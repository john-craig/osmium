## Purpose

Define executable end-to-end verification that a declaratively prepared Gitea
Actions workflow can build, sign, and publish an APK to a separate F-Droid
MicroVM and make it available to repository clients.

## ADDED Requirements

### Requirement: The publishing topology is fully declarative

The integration check SHALL boot separate Gitea and F-Droid MicroVMs on a
deterministic network. The Gitea repository, workflow source, Actions runner,
runner registration, Android build environment, APK signing material,
publication identity, destination path, host trust, and F-Droid repository
declaration and signing material MUST be established by the test configuration
before the source event that triggers publication. The test MUST require no
interactive registration, credential entry, repository editing, or manual
service setup.

#### Scenario: Both guests become ready without manual setup

- **WHEN** the integration check boots the Gitea and F-Droid MicroVMs
- **THEN** the runner is registered, the source and destination declarations
  are prepared, and all required signing and publication credentials are
  available before the triggering source push

#### Scenario: Publication credentials are unavailable

- **WHEN** the runner cannot read its declared publication credential or the
  F-Droid guest does not authorize the matching identity
- **THEN** publication fails closed and the repository does not advertise the
  candidate APK

### Requirement: A real Gitea Actions run builds and signs the APK

The integration check SHALL trigger a workflow from a commit pushed to the
declared Gitea repository and SHALL execute that workflow through the real
Gitea Actions service and registered runner. The workflow MUST build a minimal
Android application from repository source, sign the resulting APK with the
pre-provisioned test signing identity, verify that signature before
publication, and fail if any build or signing step fails. The workflow MUST NOT
depend on an externally hosted action or network service.

#### Scenario: Source push triggers the build

- **WHEN** the declarative source-seeding unit pushes the workflow and Android
  project commit after the runner is ready
- **THEN** Gitea records an Actions run for that commit and the registered
  runner executes its build, signing, signature-verification, and publication
  steps successfully

#### Scenario: Unsigned APK cannot be published successfully

- **WHEN** the workflow output lacks the expected APK signature
- **THEN** the signature-verification step fails before publication and the
  Actions run cannot report success

### Requirement: The workflow publishes through pre-provisioned access

The Actions workflow SHALL transfer only the expected signed APK to the
declared incoming artifact path on the F-Droid MicroVM using a dedicated,
non-interactive publication identity. Host verification MUST use declared host
key material rather than disabling host-key checks. The publication credential
and APK signing secret MUST NOT be emitted by the workflow log. Arrival of the
artifact SHALL allow the F-Droid service to generate and sign a complete
repository without test-driver file injection.

#### Scenario: Signed artifact reaches the declared incoming path

- **WHEN** the workflow completes its publication step
- **THEN** the exact signature-verified APK is present at the F-Droid service's
  declared artifact path and repository generation completes successfully

#### Scenario: Publication is non-interactive and host-verified

- **WHEN** the runner connects to the F-Droid guest
- **THEN** authentication and host verification use the pre-provisioned test
  files and no password prompt, trust prompt, or disabled host-key check is
  required

### Requirement: Client probes prove repository availability

The integration check SHALL wait for the Gitea Actions run to succeed and the
F-Droid repository to become ready, then SHALL use `curl` over the MicroVM
network to retrieve a signed repository index and the published APK. The check
MUST prove that the index identifies the expected package and version, that the
downloaded bytes match the workflow artifact, and that the downloaded APK has
the expected valid application signature.

#### Scenario: Published APK is available to a repository client

- **WHEN** the Actions run and F-Droid generation have completed
- **THEN** `curl` successfully downloads the repository index and expected APK,
  the index advertises the expected package and version, the artifact checksum
  matches the workflow output, and APK signature verification succeeds

#### Scenario: Executable flake check exercises both MicroVMs

- **WHEN** `nix build .#checks.x86_64-linux.gitea-fdroid-action-publish --print-build-logs`
  runs
- **THEN** it boots both MicroVMs and verifies the trigger, runner execution,
  APK build and signature, authenticated transfer, F-Droid index signing, and
  HTTP availability rather than only evaluating NixOS options or building
  system closures
