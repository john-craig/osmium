## Purpose

Provides a persistent native FreeIPA LDAP and Kerberos authority with stable
naming, secure bootstrap, and explicit network and TLS boundaries.

## ADDED Requirements

### Requirement: FreeIPA runs as a native Osmium service
The system SHALL provide a disabled-by-default `services.osmium.freeipa` service
using the pinned Nixpkgs FreeIPA package and SHALL NOT use a mutable container
image or runtime package download. It SHALL expose typed declarations for a
stable FQDN, DNS domain, Kerberos realm, LDAP and Kerberos guest and host ports,
state path, and protected bootstrap inputs. The service SHALL reject a hostname
that is not fully qualified, forward/reverse-resolvable, or compatible with the
declared domain and realm.

#### Scenario: Valid FreeIPA service starts
- **WHEN** an operator enables FreeIPA with a valid stable FQDN, domain, realm, network mapping, and runtime bootstrap inputs
- **THEN** the MicroVM starts the directory and Kerberos services and accepts authenticated LDAP and Kerberos requests

#### Scenario: Naming prerequisites are invalid
- **WHEN** the FQDN is unresolvable, reverse resolution mismatches, or the domain and realm declarations are inconsistent
- **THEN** evaluation or readiness fails with an actionable diagnostic before exposing a partial directory service

### Requirement: State, TLS, and bootstrap credentials are safe
The system SHALL persist the supported FreeIPA LDAP, Kerberos, CA trust, and
service state across impermanent guest recreation. It SHALL bootstrap the
Directory Manager and exactly one normal administrative account from separate
runtime password files, persist only secret-free completion state, and rotate
each credential when its source file changes. Bootstrap passwords, private keys,
session credentials, and Kerberos tickets MUST NOT enter the Nix store, generated
configuration, process arguments, journal, readiness output, ledger, or reverse
configuration artifacts. An invalid replacement MUST preserve the prior working
credential and completion state.

#### Scenario: Administrator input changes
- **WHEN** a runtime administrator password file is replaced with a different valid value
- **THEN** the new password authenticates, the old password is rejected, and only secret-free rotation metadata is persisted

#### Scenario: Bootstrap replacement fails
- **WHEN** a bootstrap password replacement is empty, unreadable, or rejected
- **THEN** FreeIPA remains recoverable with its prior credential and the replacement is not marked complete

### Requirement: Service scope and network exposure are explicit
The service SHALL expose LDAP, LDAPS, and Kerberos only through explicitly
declared guest and host ports and TLS trust material. It SHALL provide the
FreeIPA-internal CA and service certificates required for LDAP/Kerberos operation
but SHALL NOT declare or manage integrated DNS zones, host enrollment, service
principals, certificate issuance for consumers, sudo/HBAC policy, replicas, or
high availability.

#### Scenario: Unsupported identity-platform feature is requested
- **WHEN** an operator declares integrated DNS, a host enrollment, a consumer service principal, certificate issuance, HBAC/sudo policy, or replication feature
- **THEN** evaluation rejects the unsupported declaration rather than silently enabling an unreviewed FreeIPA subsystem

### Requirement: FreeIPA lifecycle is exercised in a MicroVM
The implementation SHALL provide a booting `freeipa` flake check that starts the
service, performs authenticated LDAPS and Kerberos operations, verifies
bootstrap and changed-file rotation, recreates the guest, and proves persistent
state. The executable command SHALL be `nix build
.#checks.x86_64-linux.freeipa --print-build-logs`.

#### Scenario: FreeIPA integration check runs
- **WHEN** the FreeIPA flake check is executed
- **THEN** it boots a MicroVM and verifies live LDAP/Kerberos behavior, credential lifecycle, TLS trust, and persistence
