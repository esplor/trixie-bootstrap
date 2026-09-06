# Notes

Why the commands in the README look the way they do. Written down as it is discovered, so
none of it has to be worked out twice.

## Getting the repo onto a minimal install

A minimal trixie install has no git and no CA certificates, so the clone fails before it
starts. `ca-certificates` is a Recommends of both `git` and `libcurl3t64-gnutls` (git's
HTTPS transport), never a Depends, so with `--no-install-recommends` it has to be named or
the clone dies with `server certificate verification failed. CAfile: none`:

```sh
sudo apt update && sudo apt install --no-install-recommends ca-certificates git openssh-client
```

Or skip the clone and copy the one script over from another machine: `scp bootstrap.sh user@host:`.

## bootstrap.sh

Three steps, each guarded, so a re-run on a configured machine is a no-op that just reports
versions.

- **curl** plus `ca-certificates`, which is only a Recommends of `libcurl4t64` and so is
  missing on a minimal install. Without it curl cannot verify TLS.
- **python3-apt**, which drags in `python3` as a hard Depends. A minimal install has
  neither, the uv project refuses to download an interpreter, and Ansible's apt module
  needs the bindings. The guard probes `/usr/bin/python3` by name, since that is the
  interpreter Ansible looks in and the only one the bindings are built for, whatever
  `python3` happens to be on `PATH`.
- **uv**, via the Astral installer with `UV_NO_MODIFY_PATH=1`. Without that flag the
  installer appends a line to `.profile`, `.bashrc`, `.bash_profile`, `.bash_login`,
  `.zshrc`, `.zshenv` and a fish conf.d file. Those are stowed symlinks into the dotfiles
  repo here, so the installer would be editing that repo. It also means no
  `~/.local/bin/env` file is written, since the installer only creates one as part of the
  same rc-file work.

uv lands in `~/.local/bin`. A script cannot put that on the `PATH` of the shell that
started it, so the run ends with a tip: log out and back in, or `. ~/.profile`. Debian's
`~/.profile` adds `~/.local/bin` only when the directory already exists at login, which it
did not before the first run.

The apt calls go through `sudo env DEBIAN_FRONTEND=noninteractive`. Without it a non-tty
run makes debconf try dialog, readline and teletype, fail all three, and fall back to
noninteractive anyway, four warning lines per install. sudo strips the variable from the
environment, hence `env`.

## The uv project

`ansible-core` is a regular dependency, `ansible-lint` a dev one. Both `uv sync` and
`uv run` install the default groups, so a plain `uv run` would quietly reinstall the lint
tooling that a `--no-dev` sync just left out. Rather than repeat `--no-dev` on every
command, `default-groups = []` makes dev opt-in: plain `uv sync` and `uv run` stay lean,
and linting is `uv run --group dev ansible-lint base.yml` when you want it.

`python-preference = "only-system"` pins uv to trixie's own Python 3.13, so no machine ends
up with a second interpreter it did not ask for. There is no `.python-version`, since
pinning one invites uv to fetch a matching build.

## base.yml

Installs the base package set and makes sure `~/.config` exists.

That directory matters more than it looks: if it is missing when stow runs, stow folds the
tree and makes `~/.config` a symlink into the dotfiles package, so everything later written
there lands inside the dotfiles repo. With a real directory in place, stow links only the
entries below it.

Two details in the play:

- `ansible_python_interpreter` is pinned to `/usr/bin/python3` so the apt module finds
  `python3-apt` directly instead of respawning out of `.venv`.
- The `~/.config` task drops `become`, and uses `lookup('env', 'HOME')` rather than a fact.
  With play-level `become: true`, facts are gathered as root, so `ansible_env.HOME` and
  `ansible_user_dir` report `/root` for the whole play, even inside a `become: false` task.

Add `-K` when sudo wants a password. The "no inventory was parsed" warning is expected: the
only host is the implicit localhost.

## neovim.yml

trixie ships neovim 0.10, too old for the lazy.nvim config in the dotfiles, so this builds
the pinned stable tag the way `~/.debian-scripts/nvim-build.sh` did and installs it to
`/usr/local`.

The first run installs the build dependencies, shallow-clones the tag and compiles, about
two minutes on a 2-core VM, then deletes the build tree from an `always` block so a failed
build cleans up too. Later runs compare `nvim --version` against `nvim_version` and skip
the whole block, so upgrading means bumping that variable.

`become` is scoped to the apt task and `make install` only, leaving the clone and the build
owned by the invoking user.

The build dependencies are exactly upstream's list for the tag (`BUILD.md`, Ubuntu/Debian):
build-essential, cmake, curl, gettext, git, ninja-build. `nvim-build.sh` also installed
unzip, luarocks and python3-venv, and a build from a fresh install with all three absent
succeeds, so none of them is a build dependency.

All three are mason **runtime** dependencies instead, and belong with the nvim config
rather than the build:

- `unzip`, to extract zip release assets (`mason-core/installer/managers/std.lua` spawns
  `unzip -d .`, and `mason/health.lua` checks for it)
- `luarocks`, for luarocks-provided packages (`mason/health.lua`, and
  `installer/compiler/link.lua` resolves bin paths through the luarocks manager)
- `python3-venv`, because mason's PyPI installer runs `-m venv --system-site-packages`
  (`mason-core/installer/managers/pypi.lua`) before pipping the tool in

The Python tools in this config are black and ruff, so `uv tool install ruff` would avoid
mason's venv path for those, uv being on every machine here anyway.

## What the nvim config will need

Not installed by anything here yet; the list for a future nvim playbook. Taken from
`vim.fn.executable()` checks in the installed plugins plus the tool lists in the config,
then checked against trixie.

| Package | Wanted by |
| --- | --- |
| `fd-find` | neo-tree (`fd`/`fdfind`), telescope |
| `nodejs`, `npm` | mason's npm tools: prettier, prettierd, markdownlint, jsonlint |
| `imagemagick` | image.nvim (`magick`, `convert`, `identify`) |
| `lazygit` | snacks.nvim's lazygit picker |
| `xdg-utils` | lazy.nvim (`xdg-open`) |
| `unzip`, `luarocks`, `python3-venv` | mason at runtime, see above |

Already covered: `ripgrep` and `build-essential` from `base.yml`, `curl` from
`bootstrap.sh`, `git` from the clone. build-essential does more work than it looks, it is
what lets `telescope-fzf-native` run its `build = "make"` and nvim-treesitter compile
parsers.

`stylua`, `vale`, `hadolint` and `prettier` are not packaged in trixie at all; mason pulls
them from GitHub releases or npm, which is the other reason it wants unzip, curl and npm.

Two nuances:

- image.nvim defaults to the `magick_cli` processor, so plain `imagemagick` suffices. Only
  the optional FFI `magick_rock` processor needs luarocks plus `lua5.1`/`liblua5.1-0-dev`.
- `markdown-preview.nvim` is configured with `build = ":call mkdp#util#install()"`, the
  prebuilt-binary path, so it needs no node despite the plugin's reputation.

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
