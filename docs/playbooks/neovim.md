# neovim.yml

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
succeeds, so none of them is a build dependency. They are mason **runtime** dependencies:

- `unzip`, to extract zip release assets (`mason-core/installer/managers/std.lua` spawns
  `unzip -d .`, and `mason/health.lua` checks for it)
- `luarocks`, for luarocks-provided packages (`mason/health.lua`, and
  `installer/compiler/link.lua` resolves bin paths through the luarocks manager)
- `python3-venv`, because mason's PyPI installer runs `-m venv --system-site-packages`
  (`mason-core/installer/managers/pypi.lua`) before pipping the tool in

They install from the same playbook all the same, in a second apt task that runs
unconditionally rather than inside the version-gated build block. The next section is what
that task installs and how the list was arrived at.

## What the nvim config needs at runtime


Established by copying `~/.config/nvim` into a VM that had only `bootstrap.sh` and
`neovim.yml` applied, running `nvim --headless "+Lazy! sync" +qa` and `:checkhealth`, then
adding packages until the errors stopped. Not by reading plugin sources, which got the
luarocks story wrong (see below).

A fresh install fails hard, not gracefully. Every start ended with:

```
Error in /home/<user>/.config/nvim/init.lua:
Too many rounds of missing plugins
```

The chain: `lua/plugins/neo-tree.lua` pulls in `3rd/image.nvim`, image.nvim ships a
rockspec, so lazy.nvim tries to install it as a luarock. Finding no luarocks, lazy
bootstraps its own *hererocks*, which compiles Lua 5.1 from source with
`-DLUA_USE_READLINE` and then configures LuaRocks against it. On a minimal trixie both
steps fail, one after the other:

- `luaconf.h:275:10: fatal error: readline/readline.h` — needs **`libreadline-dev`**
- `Configuring LuaRocks 3.13.0... Could not find 'unzip'` — needs **`unzip`**

image.nvim never installs, lazy retries the round on every start, and gives up with the
error above. With both packages present hererocks builds, the `magick` and `image.nvim`
rocks install, and startup is clean. `magick` is an FFI binding, so it needs no ImageMagick
headers at build time.

This corrects the earlier reading of image.nvim's source. Its default `magick_cli`
processor really does only want the `magick` binary, but that is a runtime choice and says
nothing about install time: lazy.nvim goes down the luarocks path because the *rockspec*
exists, whatever processor the config later selects.

What `neovim.yml` installs, and why:

| Package | Wanted by |
| --- | --- |
| `libreadline-dev`, `unzip` | lazy.nvim's hererocks, as above |
| `fd-find` | `Snacks.picker.explorer()`, telescope; Debian's binary is `fdfind`, which both look for |
| `imagemagick` | image.nvim, to convert anything that is not already a PNG |
| `libglib2.0-bin` | `gio`, the only trash command snacks.explorer finds on trixie |
| `luarocks` | mason's luarocks manager, distinct from lazy.nvim's hererocks |
| `python3-venv` | mason's PyPI installer runs `-m venv --system-site-packages` first |
| `wget`, `unzip` | mason core utils |
| `wl-clipboard` | the `"+` and `"*` registers |
| `xdg-utils` | `xdg-open`, behind `vim.ui.open` |

The task is deliberately outside the version-gated build block. These are needed whether or
not this run compiles anything, so a machine that already has the right nvim still gets
them.

`ripgrep`, `build-essential`, `ca-certificates` and `curl` are in that list too, even
though `base.yml` and `bootstrap.sh` already install them, for the reason spelled out under
[niri-desktop.yml](niri-desktop.md): a playbook that leans on another playbook having run
breaks on the first machine where it has not.

`git` is the one where that stopped being theoretical. It used to sit only in the
version-gated build block, so a machine that already had the right neovim skipped the whole
block and never got it, while lazy.nvim shells out to git to clone and update every plugin
on every start. The test VM hid it perfectly: by the time the playbook ran, git was already
there from cloning this repo.

Left out on purpose:

- **`nodejs`, `npm`** — mason installs most language servers through npm, so they are
  genuinely missing, but node belongs to a future development playbook alongside nvm,
  devbox and the Claude CLI. Installing trixie's node 20 from apt now would just be
  shadowed by nvm later.
- **`tree-sitter-cli`** — nvim-treesitter wants v0.26.1 and trixie ships 0.22.6, so apt
  cannot satisfy it. It belongs in the plugin spec as a source build.
- **`ghostscript`, `tectonic`, `mmdc`** — image.nvim's PDF, LaTeX and Mermaid renderers.
  Optional extras, not part of running the config.

`stylua`, `vale`, `hadolint` and `prettier` are not packaged in trixie either; mason pulls
them from GitHub releases or npm, which is the other reason it wants unzip, curl and npm.
The Python tools in this config are black and ruff, so `uv tool install ruff` would avoid
mason's venv path for those, uv being on every machine here anyway.

`markdown-preview.nvim` is configured with `build = ":call mkdp#util#install()"`, the
prebuilt-binary path, so it needs no node despite the plugin's reputation.

Two checkhealth complaints that are artifacts of testing over ssh, not missing packages:
`No clipboard tool found` (nvim only picks up `wl-copy` when `$WAYLAND_DISPLAY` is set) and
`command failed: { "infocmp", "-L" }` (no `TERM` in a headless run).

## ruff comes from uv, not from mason

`formatter.lua` picks `ruff_format` only when conform finds it on PATH
(`get_formatter_info("ruff_format").available`), and `lsp.lua` names `ruff` among the
servers, so on a machine without it Python quietly gets formatted by something else or not
at all. mason would install its own copy into a PyPI venv that serves nvim and nothing
else. `uv tool install ruff` puts one in `~/.local/bin` for the editor and the shell both,
and trixie has no ruff package to use instead.

## lazygit is built from source

trixie does package lazygit, at 0.50.0, far behind upstream. Upstream also publishes release
tarballs with a `checksums.txt`, but nvim, niri and noctalia are all built here from a pinned
tag, so lazygit is too. Bumping `lazygit_version` rebuilds it.

The catch is go. The `go.mod` of v0.66.3 asks for go 1.26.0 and trixie has 1.24, so the
toolchain comes from trixie-backports. The playbook names the versioned package,
`golang-1.27-go`, rather than `golang-go`, for two reasons: `state: present` is then enough,
where `golang-go` would need `state: latest` to move off trixie's, and ansible-lint rejects
that. And the binary has a fixed path, `/usr/lib/go-1.27/bin/go`, so nothing depends on PATH.
The price is that `lazygit_go` is raised by hand when `go.mod` outgrows it or backports drops
that package. `GOTOOLCHAIN=local` makes the first case a build failure instead of a silent
toolchain download.

Four things about the build:

- `main.version` is only set through `-ldflags`, and the version check reads it back from
  `lazygit --version`. Dropping the flag would rebuild on every run.
- Upstream vendors its dependencies, so the build needs no network beyond the clone, and
  `GOPROXY=off` holds it to that. Vendoring alone was not enough: go's VCS stamping still
  asked the proxy about the tag and left `~/go/pkg/mod/cache/download/.../v0.66.2.info`
  behind, hence `-buildvcs=false`.
- `HOME` points at the build tree, because otherwise go writes `~/go`, `~/.cache/go-build`
  and its local telemetry counters in `~/.config/go/telemetry`. They all go with the tree.
- `CGO_ENABLED=0` matches upstream's release build, so it needs no C compiler.

The go toolchain stays installed afterwards, like nvim's build dependencies.
