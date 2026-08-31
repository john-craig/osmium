## 1. Healthcheck Mechanism

- [x] 1.1 Add a reusable structured HTTP healthcheck helper for NixOS MicroVM tests
- [x] 1.2 Execute checks inside the guest, wait for the declared port, and fail on unexpected HTTP status codes

## 2. Gitea Integration

- [x] 2.1 Declare Gitea `GET /api/healthz` on guest port `3000` with expected status `200`
- [x] 2.2 Verify the healthcheck runs before the existing repository and persistence assertions

## 3. Documentation And Verification

- [x] 3.1 Document the healthcheck contract and executable Gitea verification command
- [x] 3.2 Run `nix fmt`, strict OpenSpec validation, and `nix flake check --no-build --no-update-lock-file`
- [x] 3.3 Run `nix build .#checks.x86_64-linux.gitea --print-build-logs` and record its successful result
