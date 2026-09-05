# claude-trixie-bootstrap

Turn a fresh Debian 13 (trixie) install into a working system, built one small step at a
time. Right now that is exactly one script: `bootstrap.sh`, which makes `uv` available.

## Rules

- Start small. One script, one job. No new abstraction until there is a second use case.
- No git, no uv project, no Ansible, no roles until explicitly asked for.
- POSIX `sh` house style: `#!/usr/bin/env sh`, `set -e` plus the pipefail probe,
  shellcheck-clean.
- Self-contained. Nothing here may source `~/.dotfiles`; it is not cloned yet at
  bootstrap time.
- Idempotent. Re-running on a configured machine is a no-op that just reports versions.

## Facts (do not re-derive)

- `ca-certificates` is a **Recommends** of `libcurl4t64`, not a Depends. With
  `--no-install-recommends` it must be named explicitly, or curl cannot verify TLS.
- uv is installed with the Astral installer plus `--no-modify-path`; shell rc files are
  the dotfiles' business, not this script's.

## Related, but do not copy from without being asked

- `~/code/debian-bootstrap`: earlier, half-built Ansible attempt.
- `~/.debian-scripts`: existing manual install scripts (stowed from `~/.dotfiles`), kept as-is.
