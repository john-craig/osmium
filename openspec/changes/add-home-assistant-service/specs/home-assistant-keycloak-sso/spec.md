## Purpose

Provides bounded Keycloak browser authentication for Home Assistant while
preserving native recovery and machine authentication boundaries.

## ADDED Requirements

### Requirement: Home Assistant uses a bounded Keycloak browser gateway

Because Home Assistant has no core native OpenID Connect authentication provider,
the service SHALL use a bounded Keycloak gateway for browser access. Home
Assistant SHALL bind its raw upstream only to loopback; oauth2-proxy and nginx
shall expose a separately declared browser endpoint with runtime-only Keycloak
client and cookie secrets. Evaluation SHALL verify Keycloak realm/client,
issuer, callback URL, claim restrictions, secret-file references, loopback
binding, and distinct browser/machine ports.

#### Scenario: Browser gateway declaration is valid

- **WHEN** the service references a compatible confidential Keycloak client and
  protected runtime gateway secrets
- **THEN** the browser endpoint starts while the raw Home Assistant listener is
  unavailable from the MicroVM host and peer network

#### Scenario: Browser gateway declaration is invalid

- **WHEN** the Keycloak client, callback URL, secret-file reference, required
  claim, upstream binding, or port mapping does not match
- **THEN** evaluation fails before Home Assistant or the gateway is exposed

### Requirement: Keycloak browser users receive one restricted Home Assistant identity

The browser gateway SHALL validate issuer, authorization response, nonce, state,
audience, signature, expiry, and declared claims before forwarding traffic. A
successful Keycloak browser session SHALL establish only the declared shared
restricted Home Assistant gateway user through a loopback-only native
authentication configuration. The gateway MUST strip client-supplied identity
and authorization headers. It MUST NOT claim to map individual Keycloak subjects
to distinct Home Assistant users or roles.

#### Scenario: Allowed Keycloak user reaches the dashboard

- **WHEN** a declared Keycloak user completes authorization with required claims
- **THEN** the user reaches the browser dashboard as the shared restricted Home
  Assistant gateway identity without receiving the native recovery credential

#### Scenario: Unauthorized Keycloak user is denied

- **WHEN** a Keycloak user lacks required claims or presents an invalid
  authorization response, nonce, or state
- **THEN** the browser request is denied before it reaches Home Assistant and no
  native Home Assistant session is created

#### Scenario: Identity header is spoofed

- **WHEN** a caller supplies `X-Forwarded-*`, `X-Auth-Request-*`, or
  `Authorization` identity headers to the browser endpoint
- **THEN** the gateway removes them and does not elevate or alter the shared
  Home Assistant identity

### Requirement: Native recovery and machine access remain separate

The service SHALL preserve native local recovery owner authentication and a
separate declared machine API endpoint using Home Assistant-native access tokens
or equivalent machine credentials. Browser sessions, gateway cookies, and
identity headers MUST NOT authenticate machine API calls. Native recovery access
MUST remain available if Keycloak or the gateway is unavailable.

#### Scenario: Recovery user bypasses Keycloak through its native path

- **WHEN** an operator uses the declared native recovery credential on the
  restricted recovery path
- **THEN** Home Assistant permits recovery without requiring Keycloak and does
  not expose that credential on the browser gateway

#### Scenario: Machine API uses a native token

- **WHEN** an automation client uses a valid declared native Home Assistant
  token on the machine endpoint
- **THEN** the API succeeds without a browser redirect, while absent or stale
  tokens fail

### Requirement: SSO changes fail closed and rotate at runtime

The gateway SHALL consume its Keycloak client secret, cookie secret, and shared
gateway-user native credential only from protected runtime files. Changed valid
values SHALL reload or restart the affected components and be validated before
completion. Invalid or unavailable replacements MUST fail closed and preserve
the last valid browser/recovery state without placing secret values in ledgers or
logs.

#### Scenario: Gateway credential changes

- **WHEN** a gateway secret or shared-user credential file receives a valid
  replacement
- **THEN** old relevant browser/session or native credentials are rejected as
  applicable and the replacement supports the documented path

#### Scenario: Gateway credential replacement fails

- **WHEN** a required gateway input is invalid, missing, or rejected
- **THEN** the affected browser path is unavailable rather than bypassing
  authentication, and native recovery remains explicit

### Requirement: Keycloak SSO is exercised in a MicroVM

The implementation SHALL provide `keycloak-sso-home-assistant`, a booting
Keycloak-to-Home-Assistant MicroVM check. The command SHALL be `nix build
.#checks.x86_64-linux.keycloak-sso-home-assistant --print-build-logs`. It SHALL
verify allowed browser login, required-claim denial, raw-upstream and spoofed-
header denial, native recovery access, native machine-token behavior, and
changed-secret rotation.

#### Scenario: Home Assistant SSO check runs

- **WHEN** the SSO check executes
- **THEN** it follows a live Keycloak authorization-code flow against the
  running service and proves browser, denial, bypass, recovery, and machine
  boundaries
