## Purpose

Provides declarative Authelia access-control behavior through a generic,
externally managed reverse-proxy authorization endpoint.

## ADDED Requirements

### Requirement: Access-control policy is declarative
The system SHALL expose a declarative default access policy and ordered
per-destination rules for supported domains, resources, subjects, groups, and
one-factor or two-factor policies. It SHALL reject wildcard, domain, path, group,
or policy declarations that cannot be represented safely or are ambiguous before
the service starts.

#### Scenario: Matching rule authorizes a subject
- **WHEN** an authenticated user requests a destination matching an allowed declared rule
- **THEN** the authorization endpoint returns success for that request

#### Scenario: Unmatched request is denied
- **WHEN** a request matches no allow rule and the declared default policy denies access
- **THEN** the authorization endpoint rejects the request without forwarding identity headers to an upstream

### Requirement: Generic authorization preserves the proxy boundary
The module SHALL expose the standard generic authorization endpoint for an
external reverse proxy and SHALL NOT generate a virtual host, route, upstream,
or trusted-header SSO configuration. For an authorized request, Authelia SHALL
return only its standard response metadata to the caller; forwarding selected
identity headers to applications remains the external proxy operator's explicit
responsibility.

#### Scenario: Unauthenticated browser request is redirected
- **WHEN** a loopback proxy sends a GET authorization request with valid HTTPS forwarded headers and no valid session
- **THEN** the endpoint returns the standard portal redirect response for the external proxy to relay

#### Scenario: Spoofed remote metadata is rejected
- **WHEN** a non-loopback caller or a loopback caller lacking the required trusted request metadata invokes the authorization endpoint
- **THEN** it cannot obtain an authorized response or an application identity assertion

### Requirement: Proxy authorization is exercised in a MicroVM
The implementation SHALL provide a booting `authelia-proxy-authorization` flake
check that uses the live generic endpoint with forwarded HTTPS request metadata,
verifies redirect, authorization, denial, and network-bypass behavior, and does
not rely on a bundled virtual host. The executable command SHALL be `nix build
.#checks.x86_64-linux.authelia-proxy-authorization --print-build-logs`.

#### Scenario: Proxy authorization integration check runs
- **WHEN** the proxy-authorization flake check is executed
- **THEN** it boots a MicroVM and proves the generic endpoint authenticates and authorizes live requests while direct guest-network access remains unavailable
