# claude-trixie-bootstrap

Turn a fresh Debian 13 (trixie) install into a working system, built one small step at a
time. Right now that is `bootstrap.sh`, which makes `uv` available, plus three playbooks
(`base.yml`, `neovim.yml`, `niri-desktop.yml`) run through it.

Explanations of why things are the way they are go in `docs/`, one page per playbook under
`docs/playbooks/`, written as they are discovered. `README.md` stays minimal: the commands,
nothing else.

## Rules

- `README.md` is the commands only. Anything explanatory belongs in `docs/`.
- Start small. One script, one job. No new abstraction until there is a second use case.
- Playbooks run against localhost. No roles, no inventory, no `ansible.cfg`, no Makefile
  until explicitly asked for.
- POSIX `sh` house style: `#!/usr/bin/env sh`, `set -e` plus the pipefail probe,
  shellcheck-clean.
- Self-contained. Nothing here may source `~/.dotfiles`; it is not cloned yet at
  bootstrap time.
- Idempotent. Re-running on a configured machine is a no-op that just reports versions.
- Never `git commit` or `git push` unless asked. Edit the files and stop there.

## Testing

Tested in a virt-manager VM (`debian-bootstrap-claude`, `qemu:///system`). A minimal trixie
install has no git, curl or wget, so the script is copied in over ssh rather than cloned:

```sh
scp bootstrap.sh trixie: && ssh -t trixie 'sh bootstrap.sh'
```

`ssh -t` because sudo needs a tty for its password prompt. Snapshot the VM after install
and revert between runs to test the cold path; skip the revert to test the re-run path:

```sh
virsh -c qemu:///system snapshot-create-as debian-bootstrap-claude fresh
virsh -c qemu:///system snapshot-revert debian-bootstrap-claude fresh
```

## Facts (do not re-derive)

- `ca-certificates` is a **Recommends** of `libcurl4t64`, not a Depends. With
  `--no-install-recommends` it must be named explicitly, or curl cannot verify TLS.
- uv is installed with the Astral installer plus `UV_NO_MODIFY_PATH=1`; shell rc files
  are the dotfiles' business, not this script's.
- The uv project uses the system interpreter only (`python-preference = "only-system"`,
  no `.python-version`), because trixie ships Python 3.13 and the VM should not be
  downloading a second one.
- A minimal trixie install has no `python3` at all, and the uv project is `only-system`,
  so it has nothing to build a venv from. Installing `python3-apt` covers both: `python3`
  is a **Depends** of it (unlike the `ca-certificates` case), so apt pulls in the
  interpreter without it being named.
- trixie's neovim is 0.10, too old for the dotfiles' lazy.nvim config, hence the source
  build in `neovim.yml`. The build takes ~110s on a 2 vCPU VM.
- stow folds: if `~/.config` does not exist, stow makes it a symlink into the dotfiles
  package, and everything later written to `~/.config` lands inside the dotfiles repo.
  Create the directory before stowing. Verified by experiment, not by folklore.
- With `become: true` at play level, facts are gathered as root, so `ansible_env.HOME`
  and `ansible_user_dir` are `/root` for the whole play, even inside a `become: false`
  task. Use `lookup('env', 'HOME')` for the invoking user's home in a localhost play.
- `python3-apt` is what `ansible.builtin.apt` needs. The module probes `/usr/bin/python3`
  and `/usr/bin/python` for the bindings and respawns into whichever has them, so a
  uv-managed interpreter would leave it nothing to respawn into.

## Related, but do not copy from without being asked

- `~/code/debian-bootstrap`: earlier, half-built Ansible attempt.
- `~/.debian-scripts`: existing manual install scripts (stowed from `~/.dotfiles`), kept as-is.
