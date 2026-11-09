---
name: project-subagent-management
description: Manage spec-driven project feature work in an isolated implementation session.
---

# Project Subagent Management

Use these instructions when you are a project worker receiving delegated work.
For a new feature, act as the coordinating worker; the implementation worker
operates in a separate worktree. Follow project instructions and do not exceed
the user's authorized scope. For non-feature tasks, use judgment and do not
automatically create an OpenSpec change or nested session.

## Propose and obtain approval

1. Confirm the current directory and repository root, active branch, Git status
   (including staged changes), project instructions, and OpenSpec root. Inspect
   the existing work without changing or discarding it. If Git or OpenSpec is
   unavailable or the intended project is unclear, stop and ask; do not
   initialize or repair it without authorization.
2. In the current project, use its OpenSpec proposal workflow to create a
   complete change for the requested feature. Present the proposal, design,
   requirements and tasks for review. Stop until the user explicitly approves
   that specific proposal; a request to propose is not approval to implement.
3. After approval, commit only the approved proposal artifacts in the project
   repository before creating the worktree. Preserve unrelated staged,
   unstaged, and untracked work; inspect both index and commit contents. If a
   proposal file contains unrelated changes, or an isolated commit cannot be
   made without disturbing the index, stop and ask. Record the proposal commit.

## Prepare an implementation worktree

4. Resolve the project root and home to canonical paths. The project must be
   inside home. Use a safe single-component kebab-case OpenSpec change name,
   rejecting `.`/`..`, separators and traversal. Map the project home-relative
   path to `~/.worktrees/<home-relative-project-path>/<change-name>`; e.g.
   `~/programming/by_category/homelab/panoply` and `example-feature` map to
   `~/.worktrees/programming/by_category/homelab/panoply/example-feature`.
   Check destination, parents, symlinks, Git worktree list and branch names;
   stop if the path or branch already exists or is unsafe. If the project is
   outside home, stop and ask for a safe destination.
5. Create a dedicated branch and worktree based on the proposal commit. Keep
   track of the exact branch, worktree, commit, and any created directories.
   Do not reuse or replace existing worktrees or branches.
6. Snapshot the project `.clinotes/` into the worktree `.clinotes/`, including
   ignored files, preserving contents and without overwriting destination data.
   If source memory is absent, report it; if destination memory already exists,
   copying is unsafe, or sensitive data cannot be handled safely, stop and ask.
   Preserve a baseline for comparison and do not expose memory in prompts or logs.
7. Before `alice switch`, inspect the worktree's Alice configuration and comment
   out the `project-subagent-management` skill and all `opencode-mcp` server
   registrations in that worktree only, preserving unrelated services. Comment
   any dependent configuration needed to keep evaluation valid. Do not change
   the primary workspace. These are temporary local isolation edits: record the
   exact original content and ensure they are not included in implementation
   commits or merged into main. If the configuration cannot be safely isolated
   or restored, stop and ask; do not overwrite concurrent changes.
   Run `alice switch` inside the worktree and verify it succeeds. Check generated
   and inherited OpenCode configuration and skill sources: neither the skill
   nor any OpenCode MCP bridge may be available to the implementation session.
   If global or inherited configuration still exposes either, use an authorized
   session-scoped deny/isolation mechanism and verify it; otherwise stop. If
   copying, Alice, isolation, or any prerequisite fails, preserve the worktree
   for recovery and do not start implementation.
8. Start a new implementation session with its working directory set to the
   worktree. Supply the approved change name, project instructions, and scope;
   instruct it to apply the OpenSpec change, run relevant checks, preserve user
   work, and report commits, verification and blockers. Do not delegate unrelated
   changes or deployments. Use an available session mechanism; if unavailable,
   stop and report rather than pretending a session was started.

## Verify, integrate, and reconcile

9. Once the session completes, restore only the recorded temporary Alice edits,
   preserving any concurrent legitimate workspace changes. Verify the isolation
   edits are absent from the implementation diff and commits; if restoration or
   history is ambiguous, stop and ask before merge. Then inspect its changes and status, ensure all
   intended implementation is committed, review against the approved spec, and
   independently run the required deterministic tests and builds. Report any
   unrun or failing checks. Do not merge if work is incomplete or unverified.
10. Recheck `main`, worktrees, status and merge ancestry. Merge the verified
    implementation branch into the project's `main` only if main can be safely
    updated without disturbing other work or sessions. If main is missing,
    checked out in an unsuitable worktree, dirty or conflicting, stop and ask.
    Never force a checkout, merge, reset, or discard changes. On conflict, stop
    and explain the state; do not overwrite or silently resolve user changes.
11. After successful integration, compare the source Clinotes snapshot, current
    project memory, and worktree memory. Consolidate new or changed records
    into the project memory, preserving concurrent changes and index consistency.
    Prefer Clinotes tools for semantic reconciliation; inspect record contents,
    not IDs alone. Resolve ID collisions by preserving both records with unique
    IDs and updating references; if safe reconciliation is uncertain, stop and
    ask. Do not blindly replace or delete either memory directory. Report
    whether reconciled memory is tracked, untracked, or ignored; do not stage or
    commit it without authorization.
12. Only after the merge and memory are verified, inspect the worktree for
    uncommitted, untracked, ignored, or otherwise unpreserved data. Preserve it
    and ask if any exists. Otherwise remove only the specific clean worktree
    and its merged branch with non-force Git commands; verify both are gone.
    Never use recursive deletion or force cleanup. If cleanup fails, leave the
    remaining resources intact and report exact recovery details.

Report proposal and implementation commits, session and worktree identifiers,
verification, merge outcome, memory reconciliation, and cleanup status. At any
failure gate, stop, preserve state, and tell the user what needs attention.
