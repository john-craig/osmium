# keycloak-service-sso Specification

## Purpose

Defines a shared, opt-in Keycloak single sign-on contract for applicable Osmium
browser services while preserving safe authentication for non-browser clients.

## Requirements

### Requirement: SSO declarations bind services to managed Keycloak clients

The system SHALL let an applicable service reference a declared Keycloak realm
and client through stable declaration keys. Evaluation SHALL verify issuer,
client ID, redirect URI, scopes, claims, and confidential-client secret-file
contracts across both declarations and SHALL reject missing, ambiguous,
cross-realm, or network-unreachable bindings.

#### Scenario: Service and client declarations agree

- **WHEN** an SSO-enabled service references a compatible managed Keycloak
  client
- **THEN** both sides use the same issuer, client ID, redirect URI, scopes, and
  runtime client-secret value without placing that value in the Nix store

#### Scenario: Service and client declarations disagree

- **WHEN** issuer, redirect URI, client type, scope, or secret-file contract does
  not match
- **THEN** evaluation fails before either service is activated

### Requirement: Gitea uses native OpenID Connect SSO

The system SHALL configure Gitea's supported OpenID Connect authentication
source against the declared Keycloak realm and confidential client. A successful
login SHALL establish or match the Gitea user according to an explicit stable
claim policy and SHALL NOT require the user's Keycloak password to be copied
into Gitea.

#### Scenario: Keycloak user signs in to Gitea

- **WHEN** the browser completes Keycloak authorization for a declared user
- **THEN** Gitea creates or matches the intended non-admin account and presents
  an authenticated Gitea session with the declared identity claims

#### Scenario: Unauthorized Gitea login is attempted

- **WHEN** the user is disabled, lacks a required role or group, or presents an
  invalid authorization response
- **THEN** Gitea denies the session without creating or elevating an account

### Requirement: Services without native OIDC use a bounded browser gateway

Gotify and OpenCode SHALL support an optional OIDC-aware browser gateway bound to
their declared Keycloak clients. The gateway SHALL validate issuer,
authorization response, nonce, state, audience, signature, expiry, and required
claims before forwarding browser traffic. Its cookie and client secrets SHALL
come from runtime files and SHALL rotate when changed. The upstream service
SHALL listen on a private guest address or port that is not directly exposed as
the browser endpoint.

#### Scenario: Keycloak user opens a proxied browser service

- **WHEN** a declared user completes authorization and has required claims
- **THEN** the gateway creates a protected browser session and forwards the
  request to the intended private upstream

#### Scenario: Gateway secret changes

- **WHEN** the client-secret or cookie-secret file receives a different valid
  value
- **THEN** the gateway reloads or restarts, consumes the replacement, and no
  secret content appears in evaluated or observed configuration

#### Scenario: Upstream bypass is attempted

- **WHEN** a host or untrusted guest client connects to the private upstream
  address or port instead of the SSO endpoint
- **THEN** networking policy rejects the connection

### Requirement: Machine authentication remains explicit and separate

SSO enablement MUST NOT redirect or inject browser sessions into Gotify token
submission, OpenCode automation, health checks, or other documented machine API
flows. Each enabled machine path SHALL retain its service-native runtime secret
or token, use a separately declared private or narrowly exposed endpoint, and
SHALL be covered by access-control tests. Browser identity headers MUST NOT grant
machine API authority unless the target service natively validates them.

#### Scenario: Gotify application posts a notification

- **WHEN** a client submits to the declared machine API endpoint with a valid
  Gotify application token
- **THEN** notification delivery succeeds without an interactive Keycloak flow
  and an invalid token remains rejected

#### Scenario: OpenCode automation calls its API

- **WHEN** an automation client uses the declared runtime-authenticated OpenCode
  API endpoint
- **THEN** valid service-native credentials succeed without a browser redirect
  and absent or stale credentials fail

### Requirement: Non-applicable services have explicit exemptions

The system SHALL leave F-Droid repository endpoints outside interactive SSO
because repository clients require direct index and artifact access, and SHALL
not invent SSO for filesystem snapshot tooling because it has no browser login
surface. Documentation and future service planning MUST record the applicability
decision, threat boundary, and verification approach instead of silently omitting
SSO.

#### Scenario: F-Droid client fetches repository metadata

- **WHEN** an F-Droid client requests the declared repository index or artifact
- **THEN** it receives normal repository HTTP behavior without an OIDC redirect

#### Scenario: Future service is proposed

- **WHEN** a new service has native OIDC support or can safely use the bounded
  browser gateway
- **THEN** its OpenSpec proposal, implementation tasks, and booting integration
  test include Keycloak SSO; otherwise they document and test the exemption

### Requirement: Each applicable service has an end-to-end MicroVM SSO check

The implementation SHALL provide separate checks named `keycloak-sso-gitea`,
`keycloak-sso-gotify`, and `keycloak-sso-opencode`. Each SHALL boot a configured
Keycloak MicroVM and the target service MicroVM, drive a real authorization-code
browser flow with a declared user, verify the authenticated service session,
verify a denied user or invalid response, and verify the service's machine-auth
boundary. The executable commands SHALL be `nix build
.#checks.x86_64-linux.keycloak-sso-gitea --print-build-logs`, `nix build
.#checks.x86_64-linux.keycloak-sso-gotify --print-build-logs`, and `nix build
.#checks.x86_64-linux.keycloak-sso-opencode --print-build-logs`.

#### Scenario: Per-service SSO checks run

- **WHEN** all three SSO flake checks are executed
- **THEN** each proves successful and denied Keycloak login against the live
  target service plus continued enforcement of its non-browser authentication
  boundary
