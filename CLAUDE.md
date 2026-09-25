# claude-trixie-bootstrap

`bootstrap.sh` makes `uv` available; `base.yml`, `neovim.yml` and `niri-desktop.yml` run
through it. Commands in `README.md`, reasoning in `docs/`, one page per playbook.

## Rules

- `README.md` is the commands only. Anything explanatory belongs in `docs/`, written as it
  is discovered.
- This file is rules and pointers only. It must not mirror `docs/`: a trap found while
  testing goes on the relevant `docs/` page and in a code comment, never here.
- Anonymize everything committed. No usernames, real names, emails, hostnames or LAN
  addresses; write `/home/<user>/...`, including in pasted logs and error output.
- Start small. One script, one job. No new abstraction until there is a second use case.
- Playbooks run against localhost. No roles, no inventory, no `ansible.cfg`.
- The `Makefile` holds one-line aliases for commands too long to retype, nothing else. No
  build logic, no dependencies between targets; a recipe needing a second line is a script.
- POSIX `sh` house style: `#!/usr/bin/env sh`, `set -e` plus the pipefail probe,
  shellcheck-clean.
- Self-contained. Nothing here may source `~/.dotfiles`; it is not cloned yet at
  bootstrap time.
- Idempotent. Re-running on a configured machine is a no-op that just reports versions.
- Never `git commit` or `git push` unless asked. Edit the files and stop there.
- Do not copy from `~/code/debian-bootstrap` (an earlier, half-built Ansible attempt) or
  `~/.debian-scripts` (manual install scripts, stowed from `~/.dotfiles`, kept as-is)
  without being asked.

## Testing

Cold installs in a virt-manager VM, `debian-bootstrap-claude` on `qemu:///system`. The
snapshot loop and the `LC_ALL` trap are in `docs/conventions.md`.
