## Why

Osmium tests Gitea and F-Droid independently, but does not prove that a
declaratively provisioned Gitea Actions workflow can build and sign an APK and
publish it into a separate F-Droid MicroVM. This leaves the most important
cross-service delivery path, including runner registration, publication
credentials, repository regeneration, and client-visible availability,
untested.

## What Changes

- Add a two-MicroVM integration check containing a Gitea server and Actions
  runner plus a separately networked F-Droid repository.
- Declaratively seed the Gitea user, source repository, workflow, runner
  registration, Android build inputs, APK signing material, and restricted
  publication credentials before the triggering source push occurs.
- Have the real Gitea Actions runner build and sign a minimal APK, publish it to
  the F-Droid guest's declared incoming artifact path, and allow the F-Droid
  service to generate and sign its indexes from that artifact.
- Verify the Actions run completes successfully and use `curl` against the
  F-Droid guest to prove that the index advertises the package and that the
  published APK is downloadable and retains a valid APK signature.
- Expose the scenario as the flake check
  `checks.x86_64-linux.gitea-fdroid-action-publish`.

## Capabilities

### New Capabilities

- `gitea-fdroid-action-publishing`: End-to-end MicroVM verification of a fully
  declarative Gitea Actions workflow that builds, signs, and publishes an APK to
  an F-Droid repository.

### Modified Capabilities

None.

## Impact

- Adds a new NixOS integration test and flake check, with test fixtures for a
  minimal Android project, Gitea workflow, and isolated test-only credentials.
- Exercises the existing Osmium Gitea and F-Droid modules together with the
  nixpkgs Gitea Actions runner, Android SDK/build tools, OpenSSH, and
  `fdroidserver`.
- Does not add or change production service options; publication staging,
  credentials, runner setup, and source seeding are scoped to the test
  configuration.
