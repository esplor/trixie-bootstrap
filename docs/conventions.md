# Conventions

## Testing


Everything here is exercised on a real cold install in a virt-manager VM
(`debian-bootstrap-claude`, `qemu:///system`), not just linted. A minimal trixie install
has no git, curl or wget, so the script is copied in over ssh rather than cloned:

```sh
scp bootstrap.sh trixie: && ssh -t trixie 'sh bootstrap.sh'
```

`ssh -t` because sudo needs a tty for its password prompt. Snapshot the VM after install
and revert between runs to test the cold path; skip the revert to test the re-run path:

```sh
virsh -c qemu:///system snapshot-create-as debian-bootstrap-claude fresh
virsh -c qemu:///system snapshot-revert debian-bootstrap-claude fresh
```

One trap worth knowing: do not export `LC_ALL=C` in the shell you run `ssh` from. Debian's
`/etc/ssh/ssh_config` has `SendEnv LANG LC_*` and the guest's sshd has the matching
`AcceptEnv`, so it overrides the guest's UTF-8 locale and Ansible refuses to start with
"Ansible requires the locale encoding to be UTF-8; Detected None".

## House style


- POSIX `sh`, shellcheck-clean, no dependency on anything outside a stock trixie install.
- Playbooks pass `ansible-lint` at the production profile.
- `--no-install-recommends` everywhere, with anything genuinely needed named explicitly.
