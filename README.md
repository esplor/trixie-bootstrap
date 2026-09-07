# trixie-bootstrap

Turn a fresh Debian 13 (trixie) install into a working system, one small step at a time.

```sh
./bootstrap.sh                           # curl, python3-apt, uv
uv sync                                  # ansible-core
uv run ansible-playbook base.yml         # base packages
uv run ansible-playbook neovim.yml       # neovim from source
uv run ansible-playbook niri-desktop.yml # niri desktop from source
```

Why any of it looks the way it does: [docs/](docs/index.md).
