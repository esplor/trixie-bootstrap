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

## Notes

- POSIX `sh`, shellcheck-clean, no dependency on anything outside a stock trixie install.
- `sudo` is used for the apt step, so expect a password prompt.
