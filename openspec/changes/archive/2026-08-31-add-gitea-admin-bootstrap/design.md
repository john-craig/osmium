## Context

Gitea's native administrative CLI can create users after the database and web
service are available. The bootstrap must run after Gitea starts, survive guest
root recreation, and avoid putting the password in a Nix store path.

## Decisions

### Use an explicit opt-in bootstrap block

The Gitea module will expose an administrator bootstrap block with `enable`,
`username`, `email`, and `passwordFile`. The username and email may be ordinary
Nix values. The password will be accepted only through a file path, allowing a
consumer to write `passwordFile = config.sops.secrets.gitea-admin-password.path`.
No literal password option will be provided.

### Use a persistent systemd oneshot

The module will create a dedicated oneshot ordered after and requiring
`gitea.service`. It will run as the Gitea service user with the Gitea config and
state directory, and write a completion marker inside `stateDir` only after the
CLI succeeds. The marker will be included automatically because the complete
state directory is already persisted.

The service will be disabled by default. If the marker exists, systemd will not
run the bootstrap again. Failed creation will not write the marker, allowing a
later activation to retry.

### Keep credentials out of the store

The password file will be consumed at runtime. The generated unit and command
line must reference the file or a systemd-provided credential rather than
embedding its contents in evaluated configuration. The implementation must
also avoid logging the password.

### Test with a guest-local fixture secret

The MicroVM test will provide a temporary password file through a test-only
guest fixture, configure the module with that path, boot Gitea, and verify the
bootstrap-created administrator can authenticate. It will restart the guest,
verify the same account still authenticates, and verify the completion marker
prevents a second bootstrap attempt.

## Risks / Trade-offs

- Gitea's CLI accepts passwords as an argument, so implementation must prevent
  password logging and should use systemd credentials where supported.
- A changed password file will not automatically rotate the existing account;
  rotation is intentionally outside this one-time bootstrap contract.
- SOPS decryption requires a configured key and secret declaration in the
  consuming host; the module only consumes the resulting runtime path.

## Verification

Run the actual Gitea MicroVM test:

```sh
nix build .#checks.x86_64-linux.gitea --print-build-logs
```

The test must exercise administrator creation and login inside the guest,
restart the guest, and verify the account remains available without a second
bootstrap.
