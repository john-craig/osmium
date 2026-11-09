## 1. Hermetic Test Inputs

- [x] 1.1 Add a minimal no-code Android project fixture with a stable package name, version code, and version name, and verify `aapt2` can compile and link it using the pinned Android platform and build-tools versions
- [x] 1.2 Add a Gitea workflow fixture that clones only the test Gitea repository, builds the APK, signs it with the protected runner keystore, verifies it with `apksigner`, and publishes it over host-verified SSH; verify the workflow contains no external action references, plaintext private material, disabled host-key checks, or shell tracing around credential use
- [x] 1.3 Add clearly labelled test-only SSH publication key and host-key fixtures, and verify the public/private pair and known-hosts entry match while no production module, example, or package references them

## 2. Gitea And Runner MicroVM

- [x] 2.1 Define the Gitea test node with Actions enabled and declarative administrator, publisher user, public source repository, and read-write repository credential; verify the normal Gitea reconciliation units create each resource before source seeding
- [x] 2.2 Configure a host-execution `services.gitea-actions-runner` instance with the pinned Android SDK, JDK, Git, OpenSSH, and shell tools, plus a runtime registration-token preparation unit; verify the runner registers non-interactively and appears online through the Gitea API before any source push
- [x] 2.3 Add runtime preparation for the APK signing keystore, SSH private key, known-hosts file, destination parameters, and restrictive runner ownership/modes; verify the runner service user can read required files, other unprivileged users cannot, and no secret value is passed in workflow YAML or command arguments
- [x] 2.4 Add a declarative source-seeding unit ordered after Gitea reconciliation, runner readiness, and credential preparation that commits the fixtures and pushes exactly once through the managed read-write repository key; verify its pushed commit is the event associated with the resulting Gitea Actions run

## 3. F-Droid MicroVM

- [x] 3.1 Define the separate F-Droid test node, deterministic inter-guest networking, SSH host identity, dedicated publication account, and incoming directory; verify the publication key authenticates without prompts while an unauthenticated connection fails and the account cannot modify the served repository tree or signing files
- [x] 3.2 Configure runtime F-Droid index-signing material and declare the expected package/version at the incoming APK path; verify signing files exist before generation, have restrictive ownership, and the normal Osmium F-Droid generator consumes the declared path
- [x] 3.3 Add a test-only generation ordering/retry override that waits for atomic Actions publication without changing the production F-Droid module; verify the HTTP service remains unready and does not advertise the APK while the incoming file is absent, then generates a signed repository after it arrives

## 4. End-To-End Assertions

- [x] 4.1 Add `tests/gitea-fdroid-action-publish.nix` as a two-MicroVM NixOS test whose driver only waits and observes; verify setup, runner registration, source push, build, signing, and transfer are performed by guest declarations and services rather than test-driver file injection or workflow dispatch
- [x] 4.2 Poll Gitea for the seeded commit's Actions run and require a successful terminal conclusion; verify the run used the registered runner and its job log records build, `apksigner` verification, and publication success without containing SSH private-key or keystore-password markers
- [x] 4.3 After repository readiness, use `curl` over the guest network to download the signed F-Droid index and expected APK; verify the index contains the declared package/version, the served APK checksum equals the incoming workflow artifact, `apksigner verify --print-certs` succeeds with the expected application-signing certificate, and the F-Droid index signature validates
- [x] 4.4 Exercise failure gates before the trigger by proving unauthorized publication is rejected and no candidate APK or index entry is available, and verify the workflow cannot reach its publication command when `apksigner` rejects an unsigned candidate

## 5. Flake Integration And Verification

- [x] 5.1 Register `checks.x86_64-linux.gitea-fdroid-action-publish` in `flake.nix` and verify `nix flake check --no-build --no-update-lock-file` evaluates the new check with both MicroVM nodes
- [x] 5.2 Run `nix fmt` and verify formatting leaves no unintended changes
- [x] 5.3 Run `openspec validate add-gitea-fdroid-publish-action-test --strict` and verify all proposal, design, specification, and task artifacts pass strict validation
- [x] 5.4 Run `nix build .#checks.x86_64-linux.gitea-fdroid-action-publish --print-build-logs` and report that the executable check booted both MicroVMs and passed the Gitea trigger, real runner execution, APK build and signature, pre-provisioned authenticated transfer, F-Droid index signing, `curl` index/APK availability, checksum, and downloaded-signature assertions
