# claude-trixie-bootstrap

`bootstrap.sh` makes `uv` available; `base.yml`, `neovim.yml` and `niri-desktop.yml` run
through it. Commands in `README.md`, reasoning in `docs/`, one page per playbook.

## Rules

- `README.md` is the commands only. Anything explanatory belongs in `docs/`, written as it
  is discovered.
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

## Facts (do not re-derive)

Why each is true is in `docs/`. These are the traps themselves.

- `--no-install-recommends` silently drops whatever a package only **Recommends**:
  `ca-certificates` for curl, `pipewire-pulse` and `libspa-0.2-bluetooth` for audio. Name
  them, or install a metapackage that Depends on them.
- `python3-apt` is what `ansible.builtin.apt` respawns into, and it Depends on `python3`,
  which a minimal trixie lacks entirely. A uv-managed interpreter cannot stand in for it.
- The uv project is `python-preference = "only-system"` with no `.python-version`, so it
  uses trixie's 3.13 rather than downloading a second interpreter.
- uv is installed with the Astral installer plus `UV_NO_MODIFY_PATH=1`; shell rc files are
  the dotfiles' business, not this script's.
- With `become: true` at play level, facts are gathered as root, so `ansible_env.HOME` is
  `/root` for the whole play, even inside a `become: false` task. Use
  `lookup('env', 'HOME')` for the invoking user's home.
- Create `~/.config` before stowing. If it does not exist, stow folds it into a symlink
  into the dotfiles package, and everything later written there lands in that repo.
- trixie's neovim is 0.10, too old for the dotfiles' lazy.nvim config, hence the source
  build in `neovim.yml`. ~110s on a 2 vCPU VM.
