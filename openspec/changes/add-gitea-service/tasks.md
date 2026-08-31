## 1. Service Module

- [x] 1.1 Add the Gitea service module with enablement, declarative settings, state directory, SQLite defaults, and stable service identity; verify the guest configuration evaluates successfully
- [x] 1.2 Declare the complete Gitea state directory through impermanence and configure required ownership; verify the generated persistence paths include `services.gitea.stateDir`
- [x] 1.3 Add HTTP and SSH guest/host port options plus same-instance collision assertions; verify equal HTTP and SSH host ports fail evaluation
- [x] 1.4 Add database password-file plumbing; verify secret contents do not appear in evaluated configuration or Nix store paths

## 2. MicroVM Integration

- [x] 2.1 Add a declarative Gitea guest MicroVM configuration with deterministic resources, hostname, interface, and port forwarding; verify the corresponding NixOS configuration evaluates
- [x] 2.2 Add Gitea HTTP readiness and repository API checks to the MicroVM test; verify a clean guest starts Gitea and creates a repository
- [x] 2.3 Extend the MicroVM test across a fresh guest start and verify the repository, state directory, and ownership survive

## 3. Documentation And Verification

- [x] 3.1 Document the Gitea module options, persistence contract, SQLite limitation, and example commands in `README.md`; verify the documented commands match flake outputs
- [x] 3.2 Run `nix fmt` and `nix flake check --no-update-lock-file`; verify all module evaluations and checks pass
- [x] 3.3 Review the generated systemd units and MicroVM configuration for idempotent activation; verify repeated evaluation produces no mutable runtime setup or duplicate resources

## 4. MicroVM Verification

- [x] 4.1 Build and execute the Gitea MicroVM integration test with `nix build .#checks.x86_64-linux.gitea --print-build-logs`; verify the VM boots, Gitea becomes reachable, and the test exits successfully
- [x] 4.2 Confirm the executed test covers repository creation and reboot persistence; verify the post-reboot API check succeeds and the test output contains no failed assertions
- [x] 4.3 Record the successful verification command and result in the change summary before marking the change complete
