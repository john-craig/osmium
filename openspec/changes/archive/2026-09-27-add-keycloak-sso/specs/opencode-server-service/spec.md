## MODIFIED Requirements

### Requirement: Network exposure is authenticated and explicit

The server SHALL expose only its declared guest endpoints and, in a MicroVM,
their declared host-forwarded ports. A non-loopback browser listener MUST be
protected either by the existing runtime HTTP Basic Auth or by the optional
Keycloak-authenticated browser gateway. SSO mode SHALL keep the OpenCode
upstream private and SHALL provide a separately declared, narrowly exposed
runtime-authenticated machine API path. Unauthenticated, stale, or unauthorized
credentials and browser sessions MUST NOT reach protected server APIs. Allowed
browser origins MUST be limited to the declared set.

#### Scenario: An authenticated client reaches the server

- **WHEN** SSO is disabled and a client sends the declared username and current
  password to the forwarded `/global/health` endpoint
- **THEN** the server returns a successful health response identifying its
  running version

#### Scenario: A Keycloak-authenticated browser reaches the server

- **WHEN** SSO is enabled and a declared user completes the authorization flow
  with required claims
- **THEN** the browser gateway permits access to the private OpenCode upstream
  without exposing its service-native password

#### Scenario: An automation client reaches the machine API

- **WHEN** SSO is enabled and a client supplies the current runtime OpenCode
  credential to the declared machine endpoint
- **THEN** the API responds without an interactive redirect

#### Scenario: An unauthenticated client probes the server

- **WHEN** a client omits credentials, supplies a previous password, lacks
  required Keycloak claims, or attempts to bypass the gateway
- **THEN** the request is rejected without disclosing protected server state
