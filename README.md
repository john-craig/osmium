# Osmium

Reproducible NixOS service definitions running in isolated MicroVMs and
tested with impermanent guest filesystems.

## Status

The project contains a small native NixOS HTTP service, Gitea and Gotify
integrations, and filesystem snapshot workflows. They verify that declared
state survives a reboot while the guest root filesystem is recreated.

## OpenCode Server

The OpenCode server is disabled by default and runs as a locked, lingering
`opencode` user through Home Manager. Credentials are supplied at runtime in a
host-prepared directory; the MicroVM mounts that directory read-only and keeps
it outside persistence. A complete declaration is:

```nix
services.osmium.opencodeServer = {
  enable = true;
  listenAddress = "0.0.0.0";
  hostPort = 44096;
  credentials.hostDirectory = "/run/secrets/opencode";
  workspaces.project = {
    hostPath = "/srv/opencode/project";
    guestPath = "/var/lib/opencode/workspace/project";
    readOnly = false;
  };
};
```

The host directory must be private (normally `0700`) and contain non-empty
`server.env` with `OPENCODE_SERVER_PASSWORD` plus valid provider `auth.json`.
Materialize `/run/secrets/opencode/{server.env,auth.json}` from `sops-nix` or
another runtime secret manager in a host activation service, then declare
`credentials.hostDirectory` as above. Do not use Nix `text` for secret values.
Provider authentication is bootstrapped atomically into persistent OpenCode
state and valid changed files rotate on the next reconciliation. Invalid
replacements leave the last valid provider auth in place and fail readiness.
The HTTP password is reloaded by restarting the user service; old credentials
stop working after a valid rotation.

Profiles, skills, and MCP servers can be declared together. Profile rules are
ordered, skill sources are immutable, and MCP credentials are resolved only at
runtime:

```nix
services.osmium.opencodeServer = {
  enable = true;
  skills.facts.path = ./skills/facts;
  mcpServers.facts = {
    type = "local";
     command = [ "/usr/local/libexec/facts-mcp" ];
    environment.MCP_TOKEN = "{env:MCP_TOKEN}";
  };
  mcpServers.remote = {
    type = "remote";
    url = "https://mcp.example.invalid/endpoint";
    headers.Authorization = "{env:MCP_AUTHORIZATION}";
  };
  profiles.facts = {
    model = "anthropic/claude-sonnet";
    rules = [ "Use verified facts." "Cite the source of each result." ];
    ruleFiles = [ ./rules/facts.md ];
    skills = [ "facts" ];
    mcpServers = [ "facts" ];
    permissions.read = "allow";
  };
};
```

Create a session first, then select the profile on the message request. A later
message may explicitly switch to another enabled profile:

```sh
curl --user opencode:PASSWORD -X POST http://127.0.0.1:4096/session -d '{}' \
  | jq -r .id > /tmp/session
curl --user opencode:PASSWORD -H 'Content-Type: application/json' \
  -X POST "http://127.0.0.1:4096/session/$(cat /tmp/session)/message" \
  -d '{"agent":"facts","parts":[{"type":"text","text":"Summarize the facts"}]}'
```

Changing `MCP_TOKEN` in the mounted environment file restarts the service and
the next MCP call consumes the replacement. Capture and drift commands include
profile state, omit secret values, and remain review-only. Profile-specific
checks are:

```sh
nix build .#checks.x86_64-linux.opencode-server-profiles --print-build-logs
nix build .#checks.x86_64-linux.opencode-server-profiles-drift-reverse-configuration --print-build-logs
nix build .#checks.x86_64-linux.opencode-server-profiles-live-capture-reverse-configuration --print-build-logs
```

To switch an existing session, send the next message with another enabled
profile name. The server rejects unknown, disabled, or removed names; it never
silently maps them to a different profile:

```sh
curl --user opencode:PASSWORD -H 'Content-Type: application/json' \
  -X POST "http://127.0.0.1:4096/session/$(cat /tmp/session)/message" \
  -d '{"agent":"audit","parts":[{"type":"text","text":"Review the result"}]}'
```

For rollback, restore the previous `server.env` and provider `auth.json`
contents in the runtime secret directory, then run
`systemctl start osmium-opencode-reconcile.service`. The service restarts only
when the file digest changes; invalid replacements fail closed and preserve the
last valid provider credentials.

### Same-Server Support Profile

Enable the bounded support coordinator explicitly and provide its model:

```nix
services.osmium.opencodeServer.supportProfile = {
  enable = true;
  model = "local/mock";
  toolProfile = "full"; # or "essential"
};
```

This generates the `osmium-support` profile and local `opencode-support` MCP entry. It
connects only to the guest listener, consumes the mounted password through
`{env:OPENCODE_SERVER_PASSWORD}`, and sets `OPENCODE_AUTO_SERVE=false`. The
support profile can inspect, create, and message same-server sessions, including
sessions created by `opencode attach`; unrelated profiles cannot use this MCP.
The task store is persisted below the OpenCode data directory. Password rotation
restarts the parent service and replaces MCP subprocesses. Observation and drift
outputs include non-secret support state, mark unresolvable host/package inputs,
and remain review-only. Disable `supportProfile.enable` to roll back without
deleting sessions or task records.

The generated names can be changed with `supportProfile.name` and
`supportProfile.mcpName`; `supportProfile.package` may select a reviewed package
override, while `toolProfile = "essential"` exposes only the core session and
messaging catalog. The default `full` catalog is required for the complete
inspection and workflow surface. The MCP endpoint is always the same guest server,
not a second OpenCode instance. Its runtime password is read from the mounted
environment file, never from the Nix store, generated JSON, process arguments, or
reverse-configuration output.

The primary MicroVM check boots the service, exercises the running HTTP API and
support MCP, and drives a real `opencode attach` client through a PTY. It verifies
same-server session visibility, deterministic provider responses, runtime-only
credentials, persistence, and password rotation. Use `toolProfile = "essential"`
when only the core session and messaging tools are needed; `"full"` is the default.

Reverse configuration is review-only:

```sh
osmium-opencode-observe > /tmp/opencode-capture.json
osmium-opencode-drift > /tmp/opencode-drift.json
```

Outputs omit secret bytes and mark host-only source paths unresolved and
incomplete. Package source identity, readiness, protocol health, and observed
runtime status is recorded as runtime provenance; live session facts remain an
explicit unresolved input because querying that endpoint changes OpenCode's
bookkeeping. Missing or unrepresentable source/package inputs keep a candidate
non-activatable. Conversion and capture do not mutate the service, sessions,
credentials, persistence, or task store. Review
and supply unresolved inputs before activation. Run the booting checks with:

```sh
nix build .#checks.x86_64-linux.opencode-server --print-build-logs
nix build .#checks.x86_64-linux.opencode-server-drift-reverse-configuration --print-build-logs
nix build .#checks.x86_64-linux.opencode-server-live-capture-reverse-configuration --print-build-logs
nix build .#checks.x86_64-linux.opencode-mcp-support-profile --print-build-logs
nix build .#checks.x86_64-linux.opencode-mcp-support-profile-drift-reverse-configuration --print-build-logs
nix build .#checks.x86_64-linux.opencode-mcp-support-profile-live-capture-reverse-configuration --print-build-logs
```

The drift check changes the running generated support state, derives a candidate
from that mutation, checks secret exclusion and non-mutation, and replays the
represented endpoint/tool profile in a second MicroVM. The live-capture check
performs real session listing and messaging, captures twice for deterministic
output, and replays the captured runtime facts in a second MicroVM. To roll back a
reviewed declaration, remove or disable `supportProfile`, then run the normal
reconciliation service; existing sessions and persisted task records are retained.

## Design

- Services are native NixOS modules whenever possible.
- Each service is intended to run in its own MicroVM.
- Runtime state must be declared through impermanence.
- Flake inputs and service versions must be pinned.
- Configuration should be safe to evaluate and activate repeatedly.

Osmium is the canonical active namespace. The compatibility module accepts the
legacy `services.mythoclast.*` and `mythoclast.host` option paths, exposes
bounded legacy command and systemd aliases, and rejects conflicting old/new
declarations rather than creating duplicate services. On first activation it
can migrate known persisted state, snapshot metadata, and credential markers
to Osmium paths. The migration is repeatable and does not copy secret contents
into logs or generated configuration.

The examples are exposed as `nixosConfigurations.demo-guest`,
`nixosConfigurations.gitea-guest`, `nixosConfigurations.fdroid-guest`, and
`nixosConfigurations.demo-host`.

## F-Droid Repository

The F-Droid repository service is disabled by default and publishes one
read-only repository from a persistent guest directory. It accepts prebuilt,
signed APKs and generates F-Droid metadata and signed indexes at startup with
the pinned `fdroidserver` package:

```nix
services.osmium.fdroidRepository = {
  enable = true;
  repositoryId = "example";
  name = "Example Repository";
  description = "Reviewed applications";
  baseUrl = "https://repo.example.invalid/repo";
  guestPort = 8080;
  hostPort = 38080;
  signing = {
    keystoreFile = config.sops.secrets.fdroid-keystore.path;
    passwordFile = config.sops.secrets.fdroid-password.path;
    keyAlias = "fdroid";
  };
  artifacts.example = {
    packageName = "org.example.app";
    versionCode = 1;
    versionName = "1.0";
    path = ./org.example.app.apk;
    sha256 = "<64 hexadecimal characters>";
  };
};
```

`baseUrl` is the client-facing URL ending in `/repo`; the guest HTTP server
serves that root on `guestPort`, and a MicroVM host forwards `hostPort` to it.
The service fails closed when the keystore or password file is missing or
unreadable. Secret contents are read only at runtime and are never placed in
the Nix store, unit arguments, generated ledger, logs, or reverse-configuration
output.

The complete repository tree, generation ledger, APKs, indexes, and readiness
marker persist below `stateDir` (default `/var/lib/fdroid-repository`). Startup
generation is idempotent once `.ready` exists. Removing an artifact declaration
does not delete persisted files; destructive cleanup remains an operator
action. A repository is ready only after generation succeeds and `.ready` is
present.

Reverse configuration is review-only. Run `observe` or `drift`, then `convert`
and inspect the deterministic, provenance-bearing candidate. `validate` rejects
incomplete or ambiguous candidates, while `reconcile` only projects a reviewed
candidate and never changes the running repository or source files:

```sh
osmium-fdroid-repository drift --output /tmp/fdroid-drift.json
osmium-fdroid-repository convert --input /tmp/fdroid-drift.json --output /tmp/fdroid-candidate.json
osmium-fdroid-repository validate --input /tmp/fdroid-candidate.json
osmium-fdroid-repository reconcile --input /tmp/fdroid-candidate.json --output /tmp/fdroid-reconciliation.json
```

Missing signing references, missing artifacts, checksum conflicts, and
unsupported state remain explicit findings and cannot be activated. Capture
does not read private keys or passwords.

## Gotify

Gotify is disabled by default. It runs through the native NixOS Gotify module,
persists `/var/lib/gotify`, and exposes an explicit guest/host HTTP mapping.
Administrator and user passwords are runtime files readable by `gotify`; they
are never put in evaluated configuration or the Nix store:

```nix
services.osmium.gotify = {
  enable = true;
  httpPort = 8080;
  hostHttpPort = 38080;
  admin = {
    enable = true;
    username = "admin";
    passwordFile = config.sops.secrets.gotify-admin-password.path;
  };
  users.alerts = {
    username = "alerts";
    passwordFile = config.sops.secrets.gotify-alerts-password.path;
  };
  applications.alerts = {
    owner = "alerts";
    name = "alerts-client";
    description = "Application notifications";
    output = {
      secretPath = "/var/lib/gotify/credentials/alerts.token";
      owner = "gotify";
      group = "gotify";
      mode = "0400";
    };
  };
};
```

Application tokens are generated once and written atomically to their protected
output. The non-secret ledger stores IDs and metadata but never passwords,
tokens, or reversible digests. A missing token output fails closed and requires
explicit recovery; application-token rotation is intentionally unsupported.
Changing a declared user password file updates that user's password during
reconciliation. Reverse tools are review-only and mark password and token
outputs unresolved:

```sh
osmium-gotify capture --output /tmp/gotify-capture.json
nix build .#checks.x86_64-linux.gotify --print-build-logs
nix build .#checks.x86_64-linux.gotify-provisioning --print-build-logs
nix build .#checks.x86_64-linux.gotify-drift-reverse-configuration --print-build-logs
nix build .#checks.x86_64-linux.gotify-live-capture-reverse-configuration --print-build-logs
```

## Gitea

Enable Gitea in a guest with:

```nix
services.osmium.gitea = {
  enable = true;
  hostHttpPort = 3001;
  hostSshPort = 2223;
};
```

The module uses SQLite and persists the complete `stateDir` (`/var/lib/gitea`
by default), including repositories, attachments, LFS data, and the database.
External database support and reverse-proxy/TLS configuration are intentionally
left for later changes. Use `databasePasswordFile` for a secret file rather
than putting a password in the Nix configuration.

Enable one-time administrator bootstrap with a runtime password file:

```nix
sops.secrets.gitea-admin-password = {
  sopsFile = ./secrets.yaml;
  owner = "gitea";
  group = "gitea";
  mode = "0400";
};

services.osmium.gitea.admin = {
  enable = true;
  username = "admin";
  passwordFile = config.sops.secrets.gitea-admin-password.path;
};
```

The bootstrap creates the administrator after Gitea starts and records a
completion marker inside `stateDir`. It does not rotate or change the account
on later starts.

Administrator credential rotation can be enabled with a replacement secret:

```nix
services.osmium.gitea.admin.rotation = {
  enable = true;
  passwordFile = config.sops.secrets.gitea-admin-rotation-password.path;
  maxAge = 90 * 24 * 60 * 60;
  checkInterval = 60 * 60;
};
```

A changed replacement credential is applied during configuration activation.
The periodic check also rotates credentials after `maxAge` and retries failed
rotations. A failed rotation leaves the current credential usable and does not
record success; disabling rotation does not revert a completed rotation.

The module also supports declarative Gitea users and organizations. Reconciled
records are updated in place, but removing a declaration does not delete an
existing Gitea record. Password-file changes trigger password rotation without
putting the password value in the Nix store or logs.

Declarative non-admin users and organizations can be provisioned with runtime
password files:

```nix
services.osmium.gitea.users.project-user = {
  username = "project-user";
  email = "project-user@example.com";
  passwordFile = config.sops.secrets.gitea-project-user-password.path;
};

services.osmium.gitea.organizations.project = {
  name = "project-org";
  owner = "project-user";
  description = "Declarative project organization";
  visibility = "private";
};
```

Users are created without administrator privileges and organizations are
created after their declared owner exists. Reconciliation is idempotent and
updates declared metadata, while removing a declaration does not delete or
transfer an existing Gitea record. Changing a user's secret-file value rotates
that user's password during reconciliation.

Repositories can be declared by stable owner/name identity. The owner is either
an available user or organization, and repository declarations manage metadata
only:

```nix
services.osmium.gitea.repositories.project = {
  owner.user = "project-user";
  name = "project-repository";
  description = "Declarative project repository";
  private = true;
  defaultBranch = "main";
  website = "https://example.com/project-repository";
  issues = true;
  wiki = false;
  pullRequests = true;
  contentScope = "metadata-only";
};
```

Repositories are created after their declared owners and reconciled through the
runtime Gitea API. Existing content and history are preserved, supported
metadata is updated in place, and removing a declaration does not delete or
transfer the repository. The module persists repository state with `stateDir`
and reads the administrator credential from its configured secret-file path at
runtime; secret contents are not evaluated into Nix or stored in markers.

Repository reverse configuration is review-only. Drift conversion compares
declared and observed owner/name records and supported metadata. Live capture
uses the runtime Gitea API, preserves user and organization ownership, sorts
records deterministically, and records provenance and incomplete or unsupported
state. Both paths omit passwords, tokens, deploy keys, webhook secrets, and
repository contents. Review the generated candidate, provide any required
secret-file references, evaluate it, and activate it through the normal NixOS
workflow; capture and conversion do not mutate Gitea or source state.

### Reverse Configuration Export

Enable the review-only exporter alongside drift detection:

```nix
services.osmium.gitea.reverseConfiguration.enable = true;
```

Generate a sanitized drift snapshot first, then export selected records without
changing Gitea or the repository:

```sh
osmium-gitea-drift --json --output /tmp/gitea-drift.json
osmium-gitea-export --input /tmp/gitea-drift.json \
  --user project-user --organization project-org --output /tmp/gitea-candidate.nix
```

Use `--json` for machine-readable candidates and exclusions. Generated users
contain an unresolved `passwordFile` requirement; fill in a reviewed secret-file
reference manually, evaluate the resulting Nix configuration, review the diff,
and activate it through the normal deployment workflow. Export never adopts
records, edits Nix source, creates adoption markers, activates configuration, or
commits changes. Administrator accounts, unsafe names, duplicate declaration
keys, external identity-provider records, and ambiguous organization owners are
reported as exclusions instead of candidates.

### Remote Capture

Enable the review-only remote capture command with
`services.osmium.gitea.remoteCapture.enable = true`. It uses a fixed,
allowlisted probe protocol over SSH and requires strict host-key verification:

```sh
osmium-gitea-remote capture --host gitea.example --user capture \
  --known-hosts ~/.ssh/known_hosts --output /tmp/gitea-capture.json
osmium-gitea-remote convert /tmp/gitea-capture.json --output /tmp/gitea-candidate.nix
```

The host, SSH identity, and optional API credentials remain operator-managed.
Capture never evaluates remote Nix, reads secret bytes, writes the remote host,
or activates a candidate. Unsupported, administrator, ambiguous, and missing
secret state is recorded as a finding and makes the candidate non-activatable.

## Development

Enter the development shell with `direnv`, or run:

```sh
nix develop
```

Evaluate the example guest:

```sh
nix build .#nixosConfigurations.demo-guest.config.system.build.toplevel
```

Run the persistence integration test:

```sh
nix build .#checks.x86_64-linux.persistence
```

Run the Gitea MicroVM integration test:

```sh
nix build .#checks.x86_64-linux.gitea --print-build-logs
```

Run the remote capture contract MicroVM check:

```sh
nix build .#checks.x86_64-linux.remote-gitea-capture --print-build-logs
```

Run the real two-node remote capture MicroVM check:

```sh
nix build .#checks.x86_64-linux.remote-gitea-capture-real --print-build-logs
```

Run the repository reverse-configuration MicroVM checks:

```sh
nix build .#checks.x86_64-linux.gitea-repository-drift-reverse-configuration --print-build-logs
nix build .#checks.x86_64-linux.gitea-repository-live-capture-reverse-configuration --print-build-logs
```

This test runs a guest-local HTTP healthcheck against Gitea's
`/api/healthz` endpoint on port `3000`, requiring HTTP `200`. It then creates a
repository through the HTTP API, restarts the guest, and verifies the
repository remains available and the Gitea state remains owned by `gitea`.

Run the rebrand compatibility checks:

```sh
nix build .#checks.x86_64-linux.osmium-rebrand-fresh --print-build-logs
nix build .#checks.x86_64-linux.osmium-rebrand-migration --print-build-logs
```

These boot MicroVMs and verify canonical Osmium units and commands, legacy
aliases, persisted state migration, snapshot metadata conversion, credential
marker migration, and service behavior after reboot.

Service tests can reuse the structured helper in `tests/healthchecks.nix`:

```nix
healthchecks.http {
  name = "service-http-health";
  port = 8080;
  path = "/healthz";
  expectedStatus = 200;
}
```

The test uses a tmpfs root and a separate persistent ext4 volume. It writes
state, reboots the guest, and verifies that the state remains available.

## Filesystem Snapshots And Reverse Configuration

The filesystem tracker is disabled by default and requires Btrfs source and
snapshot subvolumes. Both the source and all tracker state must be persistent:

```nix
services.osmium.filesystemSnapshot = {
  enable = true;
  trackers.data = {
    source = "/persistent/data";
    snapshotRoot = "/persistent/snapshots";
    stateDirectory = "/persistent/snapshots/.osmium";
    reportDirectory = "/persistent/reports";
    cacheDirectory = "/persistent/cache";
    schedule = "hourly";
    reportSchedule = "hourly";
    retentionSchedule = "daily";
    retention = { count = 10; age = 30 * 24 * 60 * 60; };
    contentThreshold = 1024 * 1024;
    exclusions = [ "cache" "tmp" ];
    redactions = [ "secrets" ];
    administrative = { user = "root"; group = "root"; mode = "0640"; };
  };
};
```

`source`, `snapshotRoot`, `stateDirectory`, `reportDirectory`, and
`cacheDirectory` must be absolute, non-escaping persistent paths and source
and snapshotRoot must differ. Exclusions and redactions are relative patterns.
The administrative user, group, and octal mode control report artifacts. The
content threshold limits emitted payloads, not hashing: changed files are
always read and hashed completely.

The baseline service creates one read-only Btrfs snapshot. Observation services
create further read-only snapshots; scheduled observations are driven by
`schedule`, and reports by `reportSchedule`. Retention, driven by
`retentionSchedule`, removes only completed, eligible snapshots and protects
the current baseline and active references. Promotion is never implicit:

```sh
systemctl start osmium-filesystem-snapshot-data-observe.service
systemctl start osmium-filesystem-snapshot-data-report.service
systemctl start osmium-filesystem-snapshot-data-promote.service
```

Set `promotionSnapshot` to the reviewed observation ID before using the
promotion unit. The baseline, observation, report, and retention units are
separate, serialized operations. A failed operation leaves the existing
baseline and last complete report in place; inspect systemd logs, correct the
source or storage problem, and rerun the specific unit. Interrupted snapshots
and comparisons are not recorded as complete.

The command interface is also available through the installed
`osmium-filesystem-snapshot` wrapper: `baseline`, `observe`, `report`,
`promote`, and `retain` operate on configured tracker paths; `validate` and
`status` consume a named JSON schema; `export` consumes a drift report; and
`deploy` consumes a bundle on stdin and requires `--destination`. Lifecycle
options include `--source`, `--snapshot-root`, `--state-dir`, `--snapshot-id`,
`--count`, `--age`, `--threshold`, `--exclude`, `--redact`, `--cache-dir`,
`--report-json`, `--report-text`, `--mode`, `--uid`, and `--gid`. Export accepts
`--bundle-output` and `--payload-dir`; deploy accepts `--destination` and
`--payload-dir`.

Reports and commands use stable statuses: `0` clean, `10` drift detected,
`20` incomplete export, `30` validation error, and `40` operational error.
Reports are deterministic and payload-free in human-readable form. Hash caching
is used only for validated immutable snapshots; large trees should be scheduled
appropriately because traversal and complete hashing remain the correctness
boundary.

The snapshot module also provides reviewable bundle export and explicit bundle
deployment. Export is non-mutating and records incomplete, redacted, or
unsupported changes instead of treating them as deletions. Deployment validates
the reviewed bundle and destination preconditions before applying it; it is
separate from export and is intentionally not advertised as atomic for a live
destination.

### Bundle Review And Deployment

Export is a review artifact generator, not an adoption operation. It writes
only stdout or the explicitly selected bundle/payload paths and does not mutate
the source tree, snapshots, baseline selection, Nix files, running system, or
version-control state. Review the manifest, operation ordering, hashes,
metadata, removals, and `incomplete` list. Exclusions remove paths from the
comparison; redactions retain classifications and hashes but never expose
payload bytes.

Oversized, redacted, unsupported, and ambiguous changes remain incomplete.
Complete them explicitly by supplying the omitted content or metadata, then
regenerate or edit the reviewed bundle and run schema validation plus deployment
preflight. Never treat an incomplete list as an implied deletion or as proof of
reproducibility. Validation checks schema/version, contained relative paths,
payload hashes, supported types, completeness, ordering, and destination
baseline preconditions before mutation.

Select an external, already-reviewed bundle only at deployment time:

```nix
services.osmium.filesystemSnapshot.trackers.data = {
  bundlePath = "/run/osmium/reviewed-bundle.json";
  bundlePayloadDirectory = "/run/osmium/payloads";
  deploymentDestination = "/persistent/data";
};
```

`bundlePath` is a runtime string path, so generated bundle contents are not
embedded in evaluated Nix configuration. A null `bundlePath` creates no deploy
unit and has no effect. A selected path enables the dedicated
`osmium-filesystem-snapshot-data-deploy.service`, which reads the bundle at
runtime, validates it, and applies it beneath `deploymentDestination`.

Deployment is explicit and distinct from export. The default deployer is
non-atomic for a live destination: a failure after preflight can leave earlier
operations applied, so stop on the first error and compare the resulting
canonical manifest before retrying. Applications writing concurrently can also
invalidate preconditions. For rollback, stop and disable the deploy unit,
restore the previously reviewed bundle or restore the destination from a
known-good snapshot/backup, and only then rerun deployment. Disabling the
tracker leaves source data, retained snapshots, reports, and exported bundles
untouched.

## Next steps

1. Extract common service metadata and MicroVM construction into `lib/`.
2. Add validation for unsupported systems and undeclared mutable paths.
3. Add CI for `nix flake check` and the MicroVM-backed tests.
