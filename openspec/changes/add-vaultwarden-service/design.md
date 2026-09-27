## Context

The repository provides native NixOS service modules, impermanent MicroVM
integration checks, runtime-only credential mounts, secret-free ownership
ledgers, and reverse-configuration checks for declarative services. The new
service must follow those patterns without introducing a database-side
provisioning path that bypasses Vaultwarden's compatibility contract.

Vaultwarden stores Bitwarden-compatible account and organization data whose
cryptographic fields are normally produced by clients. Personal-vault ciphers
are deliberately outside this change. Organization ciphers are supported only
when the operator supplies compatible pre-encrypted payloads and associated
non-secret metadata; the reconciler must never decrypt or generate plaintext
vault content.

The Keycloak SSO assessment is explicit: Vaultwarden's native Bitwarden client
protocol, account keys, master-password derivation, and encrypted sync model are
the authentication boundary. A browser gateway would not authenticate native
clients or replace vault-key derivation, so this service is an intentional SSO
exemption. The service retains native authentication and includes a boundary
test proving that no Keycloak redirect is introduced.

## Goals / Non-Goals

**Goals:**

- Provide a disabled-by-default Vaultwarden module with explicit networking,
  persistence, readiness, and runtime credential lifecycles.
- Reconcile users, optional master-password files, organizations, collections,
  memberships, and pre-encrypted organization ciphers through supported
  Vaultwarden-compatible APIs.
- Make ownership, ordering, retries, rotations, unsupported states, and
  secret-exclusion behavior reviewable and testable.
- Provide runtime-derived drift and live-capture candidates with dedicated
  booting MicroVM checks.

**Non-Goals:**

- Keycloak SSO, oauth2-proxy, identity-header injection, or a browser gateway.
- Plaintext personal-vault item provisioning or deletion.
- Generating organization encryption keys, user account cryptographic envelopes,
  or cipher ciphertext from plaintext inside Nix evaluation or persistent state.
- Importing or adopting arbitrary unmanaged Vaultwarden database rows.
- Email delivery, invitations requiring external mail, attachments, Sends,
  emergency access, policies, groups, or other resources not represented by the
  declared contract.

## Decisions

### Use the native NixOS package and an explicit loopback/upstream boundary

The module will use the pinned `vaultwarden` package already available in
Nixpkgs, run under a dedicated locked service identity, and expose only the
declared guest and host endpoints. State and attachments will be persisted
through the repository's impermanence pattern; credential mounts and
provisioning inputs remain read-only runtime dependencies.

An external reverse proxy is not added by this change. Vaultwarden remains
native-authenticated and is not routed through Keycloak. This is simpler and
preserves the protocol boundary; adding a gateway would create a misleading
browser-only authentication layer.

### Separate service lifecycle, provisioning, and observation

The module will define separate systemd units for service readiness,
provisioning reconciliation, and reverse observation/candidate generation.
Provisioning runs only after Vaultwarden is healthy and uses a runtime
provisioner credential. Observation is read-only and never invokes mutating API
operations. Each unit reports failures without claiming readiness or completed
ledger state.

### Use a versioned, secret-free ownership ledger

The ledger will contain schema version, stable declaration keys, remote IDs,
resource kind, ownership proof, non-secret metadata fingerprints, and operation
status. Password files, provisioner tokens, organization keys, encrypted cipher
payloads, and ciphertext-derived values are excluded. Atomic pending/completed
records make interruption retryable and prevent deletion of resources that
cannot be matched safely.

### Treat user master passwords as optional runtime inputs

User declarations will carry identity and account metadata independently of a
master-password file. When a file is supplied, the reconciler consumes it only
at runtime, validates the resulting account behavior, and records salted
change-detection metadata. A changed file is a credential rotation and must be
validated before the old usable state is replaced; invalid replacements leave
the last valid state and completion record intact.

When no password file is supplied, the declaration cannot claim a usable native
client credential. The candidate and readiness output will identify the
unresolved setup state without generating a password.

### Represent organization secrets as opaque pre-encrypted inputs

Organization cipher declarations will reference protected payload files or
equivalent runtime inputs containing the Bitwarden-compatible encrypted cipher
representation, stable item identity, organization/collection identity, and
required key metadata. The reconciler validates shape, ownership, and live API
acceptance but never decrypts or logs the payload. Desired-state and ledger
artifacts retain only references, stable identities, and non-secret metadata.

This is preferred over plaintext runtime inputs because it keeps the server-side
reconciler outside the users' vault decryption boundary. A plaintext mode was
considered and rejected because it would require implementing and auditing
Bitwarden key derivation and encryption, would expose plaintext during
reconciliation, and would weaken the stated client-side encryption model.

### Use supported API adapters and fail closed on cryptographic gaps

The implementation will isolate Vaultwarden endpoint and payload details behind
small adapters for account setup, organization/membership management,
collections, and encrypted cipher upload. If a requested declaration cannot be
represented by a supported API flow, the reconciler reports an explicit
unsupported or incomplete result instead of writing the database directly or
guessing cryptographic fields.

### Reverse configuration emits metadata, not vault secrets

Drift and capture will observe users, organizations, collections, memberships,
and cipher identities/metadata. They may report that an encrypted payload is
present or changed, but they will not export plaintext, keys, tokens, passwords,
or sensitive ciphertext. Such resources receive unresolved input findings and
the candidate is incomplete until the operator supplies the original protected
payload reference.

### Verify all behavior in booting MicroVM checks

The flake will expose separate checks for the base service, provisioning,
drift-reverse-configuration, live-capture-reverse-configuration, and the
explicit no-SSO boundary. Tests will use the running API/client protocol,
reboot or recreate impermanent state, mutate runtime inputs, and verify
secret-free artifacts rather than relying on option evaluation alone.

## Risks / Trade-offs

- **[Risk]** Vaultwarden's API may require client-generated cryptographic
  envelopes that cannot be safely synthesized for every user state. → Keep
  crypto-heavy fields opaque, use supported API flows only, mark unsupported
  states incomplete, and test the exact supported subset in a MicroVM.
- **[Risk]** A pre-encrypted cipher payload is sensitive even though it is not
  plaintext. → Treat payload files as runtime-only protected inputs, exclude
  them from ledgers and reverse output, and never print or hash them for output.
- **[Risk]** Optional master passwords create accounts that cannot immediately
  authenticate as native clients. → Expose unresolved setup status and make
  readiness distinguish service health from fully provisioned user credentials.
- **[Risk]** API changes could break reconciliation across Vaultwarden updates.
  → Pin the package, validate endpoint/payload assumptions in the integration
  check, and fail closed when response schemas are unsupported.
- **[Risk]** An SSO exemption could be mistaken for missing authentication.
  → Document the native-protocol rationale, keep native authentication required,
  and test that unauthorized requests fail without OIDC redirects.

## Migration Plan

1. Enable the module with persistent state and runtime credentials in a new
   MicroVM; do not import an existing database automatically.
2. Run the one-time provisioner against declared users and organization state.
   Existing unmanaged resources are observed and reported, not adopted.
3. Supply pre-encrypted organization cipher payloads through protected runtime
   paths and verify their collection and membership access with a native client.
4. For an existing Vaultwarden deployment, stop writes, back up the database and
   attachments, validate the package/API version, and restore into the declared
   persistent paths before enabling reconciliation.
5. Roll back by disabling reconciliation and restoring the last valid persisted
   state and runtime input files. Invalid credential or cipher replacements do
   not advance the ledger and therefore preserve the last valid state.
