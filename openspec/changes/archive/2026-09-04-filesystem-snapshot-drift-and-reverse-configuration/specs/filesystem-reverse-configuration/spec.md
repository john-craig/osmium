## Purpose

Provides a generic, reviewable configuration artifact that can reconstruct
supported filesystem changes observed between managed Btrfs snapshots.

## ADDED Requirements

### Requirement: Drift can be saved as a generic reconstruction configuration

The system SHALL render a versioned, deterministic configuration artifact from
a complete snapshot drift report. The artifact SHALL describe relative paths,
object types, supported metadata, removals, link relationships, and the content
representations needed to reproduce the observed state. Its format SHALL be
independent of any individual service and SHALL support validation before use.

#### Scenario: Changed file is exported

- **WHEN** a changed regular file has a reconstruction-capable content representation
- **THEN** the artifact contains its observed bytes or content delta, expected baseline hash, resulting hash, relative path, and supported metadata

#### Scenario: Added and removed paths are exported

- **WHEN** the report contains added or removed supported paths
- **THEN** the artifact contains deterministic create or remove operations sufficient to reproduce the observed tree

#### Scenario: Export is repeated

- **WHEN** the same normalized drift report is exported more than once
- **THEN** the reconstruction artifacts are byte-for-byte identical

### Requirement: Incomplete changes cannot be represented as complete

The renderer SHALL mark an artifact incomplete when a changed path lacks the
content or metadata required for reconstruction, including oversized,
redacted, unsupported, or ambiguous objects. It SHALL list every exclusion with
a machine-readable reason. An incomplete artifact SHALL NOT be accepted by the
default deployment workflow unless the operator supplies and validates the
missing state through an explicit override.

#### Scenario: Large-file content diff was omitted

- **WHEN** the report contains `content-diff-omitted` for a changed regular file
- **THEN** export identifies the path as incomplete and does not claim that applying the artifact will reproduce the observation

#### Scenario: Content was redacted

- **WHEN** reconstructable content is absent because of a redaction policy
- **THEN** export preserves the redaction reason and requires explicit content completion before validation succeeds

#### Scenario: Unsupported object is encountered

- **WHEN** drift includes a socket, device node, or another object the deployment workflow cannot safely recreate
- **THEN** the artifact excludes it from automatic reconstruction and identifies the unsupported type

### Requirement: Reconstruction application is validated and constrained

The system SHALL provide an explicit deployment operation that validates the
artifact schema, rejects absolute or escaping paths, verifies declared payload
hashes, and applies operations only beneath the configured destination root.
Application SHALL use deterministic ordering, SHALL fail before mutation when
preflight validation detects an incomplete or unsafe artifact, and SHALL report
any precondition mismatch rather than silently overwriting unexpected state.

#### Scenario: Complete artifact is deployed

- **WHEN** a complete validated artifact is configured for a destination whose baseline preconditions match
- **THEN** deployment creates, modifies, and removes supported objects beneath that destination to reproduce the observed tracked state

#### Scenario: Artifact path escapes the destination

- **WHEN** an operation contains an absolute path or resolves outside the configured destination
- **THEN** validation fails before any filesystem mutation occurs

#### Scenario: Destination differs from expected baseline

- **WHEN** a destructive or modifying operation's baseline precondition does not match the destination
- **THEN** deployment fails without silently replacing that unexpected object

#### Scenario: Payload hash is invalid

- **WHEN** embedded or referenced content does not match its declared hash
- **THEN** validation fails before that content is installed

### Requirement: Export and deployment remain distinct

Export SHALL write only to stdout or an explicitly selected operator-owned
path. It SHALL NOT modify the source filesystem, snapshots, Nix source,
baseline selection, version-control state, or running configuration. Deployment
SHALL occur only when the resulting artifact is separately selected as
configuration input.

#### Scenario: Drift is exported for review

- **WHEN** an operator saves a reconstruction artifact
- **THEN** the source filesystem, snapshot roles, repository, and active system remain unchanged

#### Scenario: Artifact is reviewed but not selected

- **WHEN** an artifact exists but is not configured for deployment
- **THEN** no filesystem operation is applied from that artifact

### Requirement: Reconstructed filesystem state is verifiable

The system SHALL provide a canonical tree-state manifest for the supported
tracked state. Equivalence SHALL cover relative paths, object types, regular
file bytes, symbolic-link targets, hard-link relationships, permissions,
ownership, modification times, and extended attributes. It SHALL exclude
filesystem-intrinsic values that cannot be reproduced, including inode numbers,
change times, Btrfs subvolume identifiers, allocation, and generation counters.

#### Scenario: Source and reconstruction are equivalent

- **WHEN** canonical manifests are generated for the observed source tree and a successfully reconstructed destination tree
- **THEN** the manifests are byte-for-byte identical

#### Scenario: File bytes differ

- **WHEN** corresponding regular files contain different bytes
- **THEN** canonical equivalence validation fails and identifies the differing relative path

### Requirement: Reverse configuration is exercised across recreated MicroVMs

The integration test SHALL boot a first MicroVM, create a managed baseline,
modify a tracked file outside the configuration workflow, detect the drift, and
save it as a generic reconstruction artifact. The test SHALL then redeploy from
the original baseline plus that artifact into a separately recreated MicroVM
and compare canonical manifests from both tracked filesystems.

#### Scenario: External file change is reproduced after recreation

- **WHEN** the first VM modifies a within-threshold file and exports its detected drift
- **THEN** a recreated VM configured with the complete artifact has a canonical tracked filesystem manifest identical to the first VM's observed manifest

#### Scenario: Export remains the tested input

- **WHEN** the recreated VM is deployed during the integration test
- **THEN** it consumes the artifact produced from the first VM's runtime observation rather than an independently authored equivalent fixture
