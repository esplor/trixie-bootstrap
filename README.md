# trixie-bootstrap

Turn a fresh Debian 13 (trixie) install into a working system, one small step at a time.

Right now that is exactly one script, `bootstrap.sh`, which brings a bare install to the
point where [uv](https://docs.astral.sh/uv/) is available. Everything built on top of this
later runs through uv.

## Getting it onto a minimal install

A minimal trixie install has no git and no CA certificates, so cloning fails before it
starts. `ca-certificates` is a Recommends of both `git` and `libcurl3t64-gnutls` (git's
HTTPS transport), never a Depends, so with `--no-install-recommends` it has to be named
or the clone dies with `server certificate verification failed. CAfile: none`:

```sh
sudo apt update && sudo apt install --no-install-recommends ca-certificates git openssh-client
```

Or skip the clone entirely and copy the single script over from another machine:

```sh
scp bootstrap.sh user@host:
```

## Usage

```sh
./bootstrap.sh
```

It installs `curl` (plus `ca-certificates`, only a Recommends of `libcurl4t64` and so
easily missed on a minimal install), then `python3-apt`, which pulls in `python3` as a
dependency (a minimal install has neither, and Ansible's apt module needs the bindings),
then uv via the Astral installer with
`UV_NO_MODIFY_PATH=1`. uv lands in `~/.local/bin`; putting that on `PATH` in new shells is
your dotfiles' job, not this script's.

Re-running on a configured machine is a no-op that just reports versions.

## The uv project

`ansible-core` is a regular dependency, `ansible-lint` a dev one. `uv sync` installs the
default groups, dev included, which is what you want in a checkout you work on. On a
machine that is only a target, skip the lint tooling:

```sh
uv sync --no-dev
```

The project pins `python-preference = "only-system"`, so uv uses trixie's own Python 3.13
and never downloads an interpreter of its own.

## The base playbook

`base.yml` installs the packages every machine wants, against this machine:

```sh
uv run --no-dev ansible-playbook base.yml
```

`uv run` syncs the default groups first, so without `--no-dev` it reinstalls the lint
tooling that `uv sync --no-dev` just left out.

It needs root for apt, so add `-K` when sudo asks for a password. The play pins
`ansible_python_interpreter` to `/usr/bin/python3` so the apt module finds the
`python3-apt` bindings rather than respawning out of `.venv`, and it warns that no
inventory was parsed, which is expected: the only host is the implicit localhost.

## Notes

- POSIX `sh`, shellcheck-clean, no dependency on anything outside a stock trixie install.
- `sudo` is used for the apt step, so expect a password prompt.
