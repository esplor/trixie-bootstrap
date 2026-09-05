# trixie-bootstrap

Turn a fresh Debian 13 (trixie) install into a working system, one small step at a time.

Right now that is exactly one script, `bootstrap.sh`, which brings a bare install to the
point where [uv](https://docs.astral.sh/uv/) is available. Everything built on top of this
later runs through uv.

## Usage

```sh
./bootstrap.sh
```

It installs `curl` (plus `ca-certificates`, only a Recommends of `libcurl4t64` and so
easily missed on a minimal install), then uv via the Astral installer with
`--no-modify-path`. uv lands in `~/.local/bin`; putting that on `PATH` in new shells is
your dotfiles' job, not this script's.

Re-running on a configured machine is a no-op that just reports versions.

## Notes

- POSIX `sh`, shellcheck-clean, no dependency on anything outside a stock trixie install.
- `sudo` is used for the apt step, so expect a password prompt.
