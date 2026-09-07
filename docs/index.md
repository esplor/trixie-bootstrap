# trixie-bootstrap

Turn a fresh Debian 13 (trixie) install into a working system, one small step at a time.

```sh
./bootstrap.sh                           # curl, python3-apt, uv
uv sync                                  # ansible-core
uv run ansible-playbook base.yml         # base packages
uv run ansible-playbook neovim.yml       # neovim from source
uv run ansible-playbook niri-desktop.yml # niri desktop from source
```

Why the commands look the way they do. Written down as it is discovered, so none of it has
to be worked out twice.

- [Getting the repo onto a minimal install](getting-started.md), which has no git or curl
- [bootstrap.sh](bootstrap.md), and [the uv project](uv-project.md) it sets up
- The playbooks: [base.yml](playbooks/base.md), [neovim.yml](playbooks/neovim.md),
  [niri-desktop.yml](playbooks/niri-desktop.md)
- [Conventions](conventions.md): how this is tested, and the house style
