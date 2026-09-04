## Context

The repository currently uses impermanence with ext4-backed persistent volumes
and has no Btrfs or generalized filesystem-observation abstraction. The active
Gitea drift and reverse-configuration changes establish useful separation
between observation, export, and activation, but their API-derived normalized
state cannot represent arbitrary filesystem objects. This change introduces a
new cross-cutting module, persistent snapshot state, a generic artifact format,
and a multi-VM integration path.

## Goals / Non-Goals

**Goals:**

- Own the complete snapshot lifecycle for explicitly configured Btrfs subvolumes.
- Produce deterministic content-aware drift reports that remain useful when inline content is size-limited.
- Produce a generic reconstruction artifact with strict completeness and safety validation.
- Prove that a runtime mutation can be exported and reproduced in a recreated MicroVM.
- Define filesystem equivalence precisely enough for an executable assertion.

**Non-Goals:**

- Inferring service intent, NixOS options, impermanence declarations, or secret-manager paths from filesystem changes.
- Automatically accepting drift, promoting baselines, editing Nix source, or committing generated artifacts.
- Reproducing inode numbers, ctimes, Btrfs allocation details, subvolume IDs, or generation counters.
- Automatically reconstructing sockets, device nodes, active process state, or files whose required contents were omitted.
- Providing transactional rollback across arbitrary applications writing concurrently to a live destination.

## Decisions

### Track explicit source subvolumes and own snapshots beneath dedicated storage

Each configured tracker will name a source Btrfs subvolume, persistent snapshot
root, schedule, retention policy, and content policy. The module will create an
initial baseline and read-only observations, record completion atomically, and
serialize snapshot, comparison, promotion, and retention operations per tracker.
Retention runs only after successful operations and protects the current
baseline and snapshots with active references.

This is preferred over integrating Snapper because Mythoclast needs explicit
baseline roles, report references, and testable lifecycle semantics rather than
Snapper's general-purpose policy model. Consuming externally managed snapshots
was rejected because enabled systems are required to create and retain their
own observation history.

### Keep baseline promotion explicit

The initial snapshot becomes the baseline. Every scheduled or manual check
creates an observation and compares it to that baseline; detecting drift does
not advance it. An operator may explicitly promote a complete observation after
review. This keeps detection stable and prevents an unreviewed mutation from
becoming accepted state merely because a timer ran.

Automatically comparing only adjacent snapshots was rejected because it loses
the cumulative difference from last accepted state. Automatically promoting
clean or drifted observations was rejected because snapshot history is not an
authorization mechanism.

### Walk read-only snapshot trees and calculate canonical state

The comparator will validate snapshots with `btrfs subvolume show` and the
read-only property, then walk each tree without following symlinks. A canonical
entry records relative path, object type, mode, numeric owner/group,
nanosecond-resolution mtime where available, xattrs, symlink target, hard-link
group, size, and regular-file content hash. Paths are byte-safe encoded in the
machine format and deterministically ordered.

Direct tree comparison is selected over treating `btrfs send` output as the
public schema. Send streams efficiently expose changes but are a binary,
version-sensitive transport format and do not by themselves provide the
normalized report, content policy, and portable reconstruction contract needed
here. The implementation may use Btrfs changed-subvolume metadata as an
optimization only if canonical traversal remains the correctness boundary.

### Require complete content comparison but bound emitted content

All changed regular files are fully hashed, regardless of size. Files at or
below the configured threshold include a reconstruction-capable representation:
a deterministic text delta when safely applicable or an exact binary-safe
replacement payload otherwise. If either version exceeds the threshold, the
report records both full hashes and sizes but omits the payload with the stable
reason `content-diff-omitted`.

Skipping reads for large files was rejected because metadata-only comparison
could miss drift. Always embedding content was rejected because reports could
grow without bound. Oversized or redacted changes deliberately make reverse
configuration incomplete until an operator supplies the missing content.

### Use a versioned manifest plus content-addressed payloads

Reverse configuration will be a generic bundle containing a canonical manifest
and content-addressed payload files. Operations describe creation, replacement,
metadata changes, links, and removals relative to a destination root, including
baseline preconditions and resulting hashes. A complete bundle can be selected
as module input and applied by a dedicated oneshot deployment unit after full
preflight validation.

A Nix-only fragment was rejected because arbitrary binary contents are awkward
to encode and the format would not be generic. A plain tar archive was rejected
because it cannot express removals, baseline preconditions, incompleteness, or
reviewable reason codes. The generic bundle may be packaged into the Nix store
by callers, but its schema does not depend on Nix.

### Fail closed on incomplete and unsafe reconstruction

Export carries every omission, redaction, and unsupported object into an
incomplete list. The default deployment path refuses incomplete bundles,
escaping paths, payload hash mismatches, unsupported object types, and baseline
precondition mismatches before mutation. Explicit completion may add missing
payloads and update the manifest, but must pass the same validator.

Best-effort reconstruction was rejected because it could report success while
silently producing a filesystem unlike the observed source. Device nodes and
sockets are excluded by default because recreating them can be privileged or
semantically invalid.

### Test runtime export through an artifact bridge between two VMs

The flake will expose a dedicated Btrfs-backed MicroVM check. Its first phase
boots a source VM, creates a baseline, mutates a within-threshold file outside
the configuration workflow, captures an observation, verifies drift, and writes
the generated bundle plus observed canonical manifest to a test-controlled
shared artifact location. The source VM is then stopped.

The second phase starts a clean VM from the same declared baseline fixture with
the runtime-generated bundle available at the configured input path. Its
deployment unit validates and applies that bundle. The test then compares the
canonical tracked-state manifest from the recreated VM with the manifest
captured from the first VM. This bridge ensures the second VM consumes the
actual runtime export rather than a separately authored expected file.

A single-VM reset was rejected because residual disk state could hide missing
reconstruction behavior. Building a new Nix closure dynamically inside the test
was also rejected as unnecessary: selecting an explicit generic artifact path
is a deployment configuration boundary and allows the complete generated
artifact to be exercised without nested Nix builds.

The check will be exposed as
`nix build .#checks.x86_64-linux.filesystem-snapshot-drift --print-build-logs`.
It is successful only after the first VM's external mutation is detected and
exported, the recreated VM consumes that exact artifact, and both canonical
tracked-state manifests compare byte-for-byte equal.

### Separate sensitive content policy from path exclusion

Path exclusions prune trees and therefore remove them from the comparison
contract. Content redaction still compares and reports a path but removes its
reconstructable payload. Reports and bundles with content are administrative
artifacts written atomically with restrictive ownership and mode. Diagnostics
must not print payload bytes.

Treating all content as sanitized was rejected because arbitrary filesystem
contents can contain credentials. Disabling content globally was rejected
because reconstruction-capable diffs are a core requirement.

## Risks / Trade-offs

- [Risk] Walking and hashing large trees can be expensive. -> Mitigation: schedule checks, expose thresholds only for emitted payloads, cache hashes keyed by validated immutable snapshot identity and metadata, and retain canonical traversal as the correctness fallback.
- [Risk] Applications may not be quiescent at snapshot time. -> Mitigation: document Btrfs crash-consistent semantics and allow per-tracker systemd ordering or pre/post snapshot hooks with failures preventing completion records.
- [Risk] Reports can contain secret file contents. -> Mitigation: support exclusions and redaction, restrict artifact permissions, never log payloads, and make incompleteness explicit.
- [Risk] Numeric ownership may not map identically on another host. -> Mitigation: preserve numeric IDs, validate deployment privileges, and compare numeric ownership in canonical manifests.
- [Risk] Applying several valid operations can fail partway because the live destination changes after preflight. -> Mitigation: apply to a staging subvolume and use an atomic subvolume switch where configured; otherwise report the non-atomic mode and stop on first mismatch.
- [Risk] Btrfs capabilities differ in virtualized test environments. -> Mitigation: create a dedicated virtual disk, format it as Btrfs inside the MicroVM, and run the required flake check on a host supporting the existing QEMU test stack.
- [Risk] Retention could remove evidence needed for review. -> Mitigation: protect current and referenced snapshots and make count/age limits explicit in reports and documentation.

## Migration Plan

Add the module disabled by default. For an existing deployment, create or select
a dedicated Btrfs subvolume and persistent snapshot root, configure exclusions
and content policy, then enable the tracker to establish its initial baseline.
Run a manual observation and inspect the first report before enabling its timer.

Rollback disables timers and deployment units but leaves source data, retained
snapshots, reports, and exported bundles untouched. Operators may remove those
artifacts separately after confirming that no baseline or reconstruction input
is still required.
