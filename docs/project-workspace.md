# Project workspace

The Alice workspace provisions Clinotes, the vendored
`project-subagent-management` skill, and the OpenCode MCP bridge from a pinned
`john-craig/nixpkgs-apocrypha` workspace module. Run `alice switch` in this
project to provision it. The bridge connects to the laptop OpenCode endpoint and
reads its password at runtime from
`$XDG_RUNTIME_DIR/secrets/opencode/server_password`; no password is committed.

Implementation worktrees temporarily disable the delegation skill and bridge
to prevent recursion. See the vendored skill for isolation and restoration.
The development shell lists its commands; each supports `--help`.
