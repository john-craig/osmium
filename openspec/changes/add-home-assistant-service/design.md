## Context

The repository already establishes an impermanent MicroVM pattern: native NixOS
service modules, runtime-only secrets, secret-free reconciliation ledgers,
Keycloak-backed browser gateways where native OIDC is unavailable, and booting
tests for both service behavior and reverse configuration. See `proposal.md` for
motivation and the four change specifications for the behavior contract.

Home Assistant's native NixOS module can render `configuration.yaml`, install
blueprints and Lovelace resources, and manage the service lifecycle. Its core
authentication providers are local users, trusted networks, and command-line
authentication; it does not include a core OIDC provider. It also separates
YAML-backed configuration from UI-managed `.storage` state, while many
integrations depend on physical host devices.

## Goals / Non-Goals

**Goals:**

- Wrap Home Assistant in the existing Osmium service, persistence, runtime
  secret, ownership-ledger, and MicroVM-check patterns.
- Render and reconcile a typed, supported declarative Home Assistant subset
  while detecting UI-only, device-backed, ambiguous, and secret-backed state.
- Add a bounded Keycloak browser gateway that maps every authorized browser
  session to one deliberately restricted Home Assistant gateway account.
- Preserve native owner recovery and token machine APIs independently from the
  browser SSO path.

**Non-Goals:**

- Per-Keycloak-subject Home Assistant users, roles, or permissions.
- Treating proxy headers as Home Assistant identity assertions.
- USB, serial, Bluetooth, Zigbee, Z-Wave, GPIO, camera, audio, or other host
  device passthrough.
- Provisioning, adopting, or deleting unsupported UI-only state or arbitrary
  external integrations.

## Decisions

### Compose the native NixOS Home Assistant module

`services.osmium.homeAssistant` will wrap `services.home-assistant` rather than
running Home Assistant in a container or independently invoking the Python
application. The wrapper will own typed configuration, persistent paths,
runtime input validation, readiness, explicit firewall/forwarding, and reverse
configuration tooling.

The native module is chosen because it pins Home Assistant and declarative YAML
rendering to nixpkgs. A container was rejected because it would duplicate the
repository's package, persistence, and secret lifecycle patterns.

### Separate immutable rendered configuration from persisted UI state

The module will render a deterministic managed configuration tree for the
declared subset and persist Home Assistant's supported state/storage tree.
Managed files will be replaced atomically on configuration changes. UI-created
objects are observed rather than silently imported; supported API-managed items
may be reconciled only after an ownership proof is recorded.

This avoids the native module's default behavior of overwriting a single
managed `configuration.yaml` while making all declared assets reproducible.

### Bootstrap native recovery and shared gateway users at runtime

A protected owner credential file bootstraps exactly one native recovery owner.
A separate restricted local user is created for the browser gateway. The
reconciler records user IDs and salted credential fingerprints, never password
bytes, then derives a small runtime authentication include that binds loopback
gateway traffic to the known restricted user.

This uses Home Assistant's documented trusted-network provider only for the
loopback proxy path and preserves the native `homeassistant` provider for
recovery. A command-line provider was rejected because it would require passing
interactive Home Assistant passwords to a Keycloak verification command and
would not establish an authorization-code browser session. A custom OIDC auth
provider was rejected for this change because it would introduce an unpinned,
non-core authentication dependency and a per-user identity model outside the
selected shared-user scope.

### Bound the gateway and preserve separate paths

Home Assistant binds only to loopback when SSO is enabled. oauth2-proxy receives
Keycloak authorization-code sessions on loopback; nginx exposes the browser
port, strips client identity headers, and proxies authenticated traffic. The
gateway has separate runtime client/cookie secret files and reloads on change.

The machine endpoint is distinct and does not run the browser auth request.
It relies solely on long-lived Home Assistant tokens. The recovery path is
loopback/restricted deployment access and native owner credentials; it is never
forwarded through the gateway. Browser sessions cannot authenticate machine API
calls.

The unavoidable trade-off of the selected shared-user model is that Home
Assistant sees all authorized Keycloak users as one restricted local user. This
is explicit in rendered UI/configuration, documentation, and tests.

### Keep machine tokens and passwords runtime-only

The module will consume owner, user, and SSO input files at runtime, generate or
validate machine tokens through supported Home Assistant APIs, and write tokens
only to protected declared runtime output paths. The ledger stores stable IDs,
scopes, paths, salts, and non-reversible fingerprints. Changed files invoke a
validate-then-replace path and leave previous usable values/ledger entries on
failure.

### Treat device-backed integrations as unsupported

Validation will reject direct device paths and hardware passthrough declarations.
Live capture labels observations that depend on unavailable hardware as
unsupported/incomplete. This avoids a hidden widening of MicroVM privileges and
leaves a later device-passthrough change with a clean security boundary.

### Provide runtime-derived reverse configuration

Observation commands will combine managed files, supported Home Assistant APIs,
and service/unit facts. They produce normalized JSON with provenance,
completeness, unsupported findings, and secret exclusions. Candidate conversion
produces review-only declarations with unresolved references for credentials,
tokens, host paths, device dependencies, and UI-only records. Neither path
changes Home Assistant, managed sources, or ledgers.

## Risks / Trade-offs

- **[Shared gateway account weakens per-person attribution]** → Restrict the
  gateway account, preserve native recovery users, document the behavior, and
  treat per-user Keycloak mapping as a future separate capability.
- **[Any guest process can originate loopback traffic]** → Keep the MicroVM
  single-purpose, bind the raw upstream only to loopback, strip headers at nginx,
  expose no host-forwarded raw port, and test external/peer bypass denial.
- **[Home Assistant UI storage evolves independently of YAML]** → Version and
  pin the package, capture only an explicit supported subset, and mark the rest
  incomplete rather than rewriting it.
- **[Credentials may not be rotatable through stable Home Assistant APIs]** →
  Probe API capability in the MicroVM test; where native mutation is unavailable,
  fail closed and retain the last valid credential rather than modifying storage
  directly.
- **[Large declarative configuration can slow reloads]** → Use atomic rendered
  files, content fingerprints, ordered reload/restart units, and no-op behavior
  for unchanged declarations.

## Migration Plan

1. Deploy a new MicroVM with loopback-only Home Assistant, persistent state, and
   protected owner/gateway/runtime token inputs.
2. Bootstrap the recovery owner and restricted gateway account before exposing
   the browser gateway; verify native recovery and token machine paths.
3. Enable the Keycloak client and gateway only after the live authorization-code
   check succeeds; do not forward the raw Home Assistant listener.
4. Add declarative configuration in stages, reviewing unsupported/incomplete
   capture findings before migrating UI-created state.
5. Roll back by disabling gateway/reconciliation units and restoring the
   persistent Home Assistant state plus last valid runtime inputs. Invalid
   replacements never advance the ownership ledger.
