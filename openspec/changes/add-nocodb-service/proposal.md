## Why

Osmium needs a self-hosted, persistent collaborative database service whose Community Edition state can be defined, reconciled, inspected, and recovered declaratively. NocoDB provides bases, tables, fields, views, collaboration, and records, but its mutable control-plane state needs an explicit service and ownership model before it can be deployed safely in impermanent MicroVMs.

## What Changes

- Add an Osmium NocoDB Community Edition service module and a pinned Nix package derivation because NocoDB is not currently packaged by nixpkgs.
- Provide persistent NocoDB application state with SQLite as the default metadata/data backend and typed PostgreSQL support, using runtime-only credentials and a stable JWT secret.
- Add one-time local-super-admin bootstrap and changed-secret credential rotation with a secret-free completion ledger.
- Add declarative Community Edition users, per-user API tokens and scopes, the instance workspace, workspace/base membership, bases (the NocoDB resource historically called a project), tables, fields, relations, views, and initial records.
- Reconcile only resources proven to be Osmium-managed, expose explicit preservation/removal policies, and reject unsupported or unsafe declarations before mutation.
- Add review-only drift detection and live-system capture that convert observed supported state into incomplete, secret-safe Nix candidates with provenance.
- Define a fail-closed Community Edition identity boundary: native Keycloak OIDC, FreeIPA LDAP/SCIM federation, organization resources, organization roles, teams, and other licensed-only NocoDB features are rejected rather than partially configured.
- Add booting MicroVM checks for service lifecycle, persistence, bootstrap/rotation, scoped API-token behavior, all declared resource types, Community Edition identity-boundary denial, drift conversion, and live capture.

## Capabilities

### New Capabilities
- `nocodb-service`: Runs NocoDB Community Edition in a persistent, secret-safe Osmium MicroVM with SQLite and PostgreSQL support.
- `nocodb-declarative-identities`: Reconciles local Community Edition users, scoped per-user API tokens, workspace membership, and base membership with explicit ownership and removal semantics.
- `nocodb-declarative-databases`: Reconciles the Community Edition workspace, bases/projects, tables, fields, relations, views, and initial records.
- `nocodb-community-identity-boundary`: Rejects licensed-only NocoDB organization and external identity features while documenting the Keycloak/FreeIPA migration boundary.
- `nocodb-reverse-configuration`: Provides safe, review-only drift and live-capture conversion for supported NocoDB declarations.

### Modified Capabilities
- None.

## Impact

- Adds `modules/packages/nocodb.nix`, `modules/services/nocodb.nix`, module imports, documentation, and NocoDB flake checks.
- Adds runtime dependencies for NocoDB and its selected SQLite or PostgreSQL backend; optional PostgreSQL configuration consumes credentials only from runtime secret files.
- Uses NocoDB's authenticated metadata and data APIs for reconciliation and observation; API credentials, user passwords, minted token values, JWT secrets, and database credentials remain runtime-only and excluded from reports, candidates, and ledgers.
- Does not change existing Keycloak or FreeIPA behavior. Community Edition cannot provide their native NocoDB federation, OIDC, SCIM, organizations, or organization roles.
