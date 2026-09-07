# Conventions

## Testing


Everything here is exercised on a real cold install in a virt-manager VM, not just linted.
See the Testing section of `CLAUDE.md` for the snapshot loop.

One trap worth knowing: do not export `LC_ALL=C` in the shell you run `ssh` from. Debian's
`/etc/ssh/ssh_config` has `SendEnv LANG LC_*` and the guest's sshd has the matching
`AcceptEnv`, so it overrides the guest's UTF-8 locale and Ansible refuses to start with
"Ansible requires the locale encoding to be UTF-8; Detected None".

## House style


- POSIX `sh`, shellcheck-clean, no dependency on anything outside a stock trixie install.
- Playbooks pass `ansible-lint` at the production profile.
- `--no-install-recommends` everywhere, with anything genuinely needed named explicitly.
