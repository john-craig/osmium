## Purpose

Provides managed Btrfs snapshots and trustworthy, content-aware reports of
filesystem changes within explicitly configured persistent subvolumes.

## ADDED Requirements

### Requirement: Configured Btrfs snapshots are managed

The system SHALL create read-only snapshots of each enabled source subvolume,
retain them according to configured age or count limits, and expose explicit
operations for creating a baseline, capturing an observation, and promoting an
observation to the next baseline. Snapshot names and metadata SHALL identify
the tracked source, creation time, and role. Retention SHALL NOT remove a
current baseline or a snapshot referenced by an in-progress comparison.

#### Scenario: Initial baseline is created

- **WHEN** snapshot drift management is enabled for a Btrfs subvolume without a baseline
- **THEN** the system creates and records a read-only baseline snapshot without changing the source subvolume

#### Scenario: Scheduled observation is captured

- **WHEN** the configured snapshot schedule elapses
- **THEN** the system creates a read-only observation snapshot and compares it with the current baseline

#### Scenario: Retention is applied

- **WHEN** completed snapshots exceed the configured age or count limit
- **THEN** the system removes eligible oldest snapshots while preserving the current baseline and snapshots used by active operations

#### Scenario: Observation becomes accepted state

- **WHEN** an operator explicitly promotes a complete observation
- **THEN** that observation becomes the baseline for future comparisons without modifying the tracked source tree

### Requirement: Snapshot pairs are validated before comparison

The system SHALL compare only complete, read-only Btrfs snapshots belonging to
the configured source lineage. It SHALL report an operational error rather than
a drift result when either snapshot is missing, writable, inaccessible,
incomplete, or associated with a different tracked source.

#### Scenario: Valid related snapshots are selected

- **WHEN** a recorded baseline and observation are complete read-only snapshots of the configured source
- **THEN** the system accepts the pair for comparison

#### Scenario: Snapshot lineage does not match

- **WHEN** either selected snapshot belongs to another configured source or cannot be validated
- **THEN** the comparison fails without classifying absent paths as removals

#### Scenario: Snapshot is writable

- **WHEN** either selected snapshot is not read-only
- **THEN** the comparison fails and identifies the unsafe snapshot

### Requirement: Filesystem drift is content-aware and complete

The system SHALL compare every non-excluded path without following symbolic
links. It SHALL classify added, removed, content-modified, metadata-modified,
link-target-modified, type-changed, and unchanged paths. Supported metadata
SHALL include file type, permissions, ownership, modification time, extended
attributes, and hard-link relationships. For every changed regular file, the
system SHALL compare content and record old and new cryptographic hashes.

#### Scenario: File contents change externally

- **WHEN** a regular file has different bytes in the observation snapshot
- **THEN** the report classifies it as content-modified and records distinct old and new content hashes

#### Scenario: File is added or removed

- **WHEN** a relative path exists in only one member of the snapshot pair
- **THEN** the report classifies the path as added or removed and records its supported state from the snapshot where it exists

#### Scenario: Metadata changes without content changes

- **WHEN** content hashes match but supported metadata differs
- **THEN** the report classifies the metadata changes without reporting a content modification

#### Scenario: Symbolic link is encountered

- **WHEN** a symbolic link exists in either snapshot
- **THEN** the comparator records and compares the link target without traversing it

#### Scenario: Path type changes

- **WHEN** an observed path has a different filesystem object type than its baseline counterpart
- **THEN** the report classifies a type change and preserves both supported object descriptions

### Requirement: Content diff size is bounded explicitly

For each changed regular file at or below the configured content-diff size
threshold, the system SHALL emit a reconstruction-capable content delta or
replacement representation. For a changed file above the threshold, it SHALL
still compare complete contents and emit old and new hashes, sizes, and an
explicit `content-diff-omitted` reason, but SHALL NOT emit the full content
delta. The threshold SHALL be configurable per tracked subvolume.

#### Scenario: Changed file is within the threshold

- **WHEN** a changed regular file is no larger than the configured threshold
- **THEN** the result includes a content representation sufficient to reconstruct the observed bytes

#### Scenario: Changed file exceeds the threshold

- **WHEN** either version of a changed regular file exceeds the configured threshold
- **THEN** the result includes complete-content hashes and sizes but marks the content delta as omitted

#### Scenario: Large files have equal contents

- **WHEN** a large file's metadata changes but its complete-content hashes match
- **THEN** the result reports only the supported metadata changes

### Requirement: Reports are deterministic and policy-aware

The system SHALL provide human-readable and versioned machine-readable reports
with deterministic path ordering and stable exit statuses for clean, drift,
incomplete-export, and operational-error outcomes. Configured exclusions SHALL
be identified without traversal, and configured content redaction SHALL remove
content representations while retaining change metadata and an explicit reason.
Reports containing unredacted content SHALL be written with access restricted
to the configured administrative identity.

#### Scenario: No drift exists

- **WHEN** a complete comparison finds no supported differences
- **THEN** check mode exits successfully and emits a clean result

#### Scenario: Drift exists

- **WHEN** a complete comparison finds one or more supported differences
- **THEN** check mode returns the documented drift status and emits deterministically ordered changes

#### Scenario: Content is redacted by policy

- **WHEN** a changed path matches a configured content-redaction rule
- **THEN** the report retains hashes and change classification but omits reconstructable contents and identifies the redaction rule

#### Scenario: Path is excluded

- **WHEN** a path matches an exclusion rule
- **THEN** the comparator does not descend into or report that path and records the applied exclusion in comparison metadata

### Requirement: Snapshot history is persistent and non-authoritative

The system SHALL persist managed snapshots, snapshot identities, comparison
state, schema versions, and report fingerprints in a declared persistent
location. Interrupted snapshot or comparison operations SHALL not be recorded
as complete. Historical state SHALL NOT authorize baseline promotion,
filesystem repair, configuration activation, or deletion outside retention.

#### Scenario: Snapshot management survives recreation

- **WHEN** an enabled MicroVM is recreated with its declared persistent Btrfs storage
- **THEN** valid retained snapshots and the current baseline remain available

#### Scenario: Comparison is interrupted

- **WHEN** collection or report generation fails before atomic completion
- **THEN** no successful observation or report is recorded and the existing baseline remains current

### Requirement: Snapshot drift is exercised in a MicroVM

The integration test SHALL boot a MicroVM with a real Btrfs source subvolume,
create managed snapshots, mutate the source outside the configuration workflow,
and run the detector. It SHALL verify content and metadata classifications,
bounded large-file behavior, retention, failure handling, and read-only
snapshot guarantees against the running system.

#### Scenario: External mutation is detected end to end

- **WHEN** the test modifies a tracked file after the baseline and captures an observation
- **THEN** the detector reports the changed path, reconstructable observed contents, and supported metadata without changing either snapshot

#### Scenario: Oversized mutation is detected without inline content

- **WHEN** the test changes a file larger than the configured threshold
- **THEN** the detector reports different complete-content hashes and an omitted content delta
