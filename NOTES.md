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

## niri-desktop.yml

niri is not packaged in trixie at all (`apt-cache policy niri` comes back empty), and
neither is xwayland-satellite, so both are built from source the way `~/code/desktop`'s
`niri-build.sh` and `xwayland-satellite-build.sh` did it by hand. Configuration stays out
of it: `~/.config/{niri,waybar,kitty}` are stow symlinks into `~/.dotfiles`, so this
playbook installs software and stops there.

Everything below was established by running it cold in the VM, not by reading the notebook
scripts, which turned out to be wrong in both directions.

### Every dependency is named here, even the ones another playbook installs

`build-essential`, `ca-certificates`, `curl` and `git` are already installed by `base.yml`
and `bootstrap.sh`, and are listed here anyway. A playbook that quietly relies on another
playbook having run is a trap on the first machine where it has not, and the test VM is the
worst place to notice, because by then everything is installed.

That is a different question from relying on a package's `Depends`. `pkg-config`,
`libglib2.0-dev` and `libcairo2-dev` are hard Depends of `libpango1.0-dev`, and
`libxcb1-dev` of `libxcb-cursor-dev`, so naming them is noise. Same reasoning as
`python3-apt` pulling in `python3`: a Depends is guaranteed, a Recommends is not.

### The build dependencies in the notebook were wrong

Upstream publishes the real lists, in `DEPS_APT` in niri's `.github/workflows/ci.yml` and
in `.github/workflows/ubuntu.dockerfile` plus the README for xwayland-satellite.

`niri-build.sh` was **missing** `clang`, `libdbus-1-dev` and `libsystemd-dev`, and nothing
else in its list pulls them in: `libudev-dev` depends only on `libcap-dev` and `libudev1`,
and none of the other `-dev` packages depends on dbus or systemd. The script worked only
because those three were already on the machine for other reasons. It also named
`pkg-config`, `libglib2.0-dev`, `libcairo2-dev` and `libxcb1-dev`, all redundant per above.

### Two prerequisites nothing else here installs

- `python3-debian`, because `deb822_repository` parses and writes `.sources` files through
  it and fails outright without it, exactly the way the apt module needs `python3-apt`. The
  module can fetch it itself via `install_python_debian`, but naming it keeps the
  dependency visible and routes it through `--no-install-recommends` like everything else.
- `fontconfig`, for `fc-cache`. Absent on a machine that has only run `bootstrap.sh`,
  `base.yml` and `neovim.yml`.

### Build in /var/tmp, never /tmp

`ansible.builtin.tempfile` defaults to `/tmp`, and `/tmp` is a tmpfs on a stock trixie. A
cargo `target/` tree built there is held in RAM: niri's is 3.8 GB and xwayland-satellite's
921 MB. On a 4 GB VM that means three OOM kills, a load average of 11, and an sshd that
stops answering mid-build. `free` gives it away with a large `shared` column, which is the
tmpfs.

Both build directories pass `path: /var/tmp`, which is the FHS home for temporary data too
large or too long-lived for `/tmp`, and is ext4 on the root filesystem. `neovim.yml` gets
away with the default only because its build tree is small.

Budget roughly 5 GB of disk and, with eight parallel `rustc` and no swap, more than 4 GB of
RAM. The VM does this comfortably on 8 cores and 8 GB.

### rustup, pinned, rather than trixie's cargo

trixie ships cargo and rustc 1.85.0, and niri 26.04 declares `rust-version = "1.85"` with a
CI job at `dtolnay/rust-toolchain@1.85.0`, so apt's toolchain would very probably build it.
rustup is used anyway, pinned to `rust_version`, because that is what upstream's docs tell
you to use and what these machines already build with. Worth knowing rather than
rediscovering: the apt route is not obviously broken, it is just not the one taken.

The installer runs with `--no-modify-path` for the same reason `bootstrap.sh` passes
`UV_NO_MODIFY_PATH=1`: the shell rc files are stowed symlinks into the dotfiles repo, and
the installer would otherwise append to six of them. Every cargo call uses an absolute path
instead of relying on PATH.

`rustup-init` refuses to run over an existing rustup, so bumping `rust_version` on a machine
that already has it goes through `rustup default` instead, which installs the toolchain if
it is missing.

### Ansible module traps, all of them found by running it

- **`get_url` and `tempfile` do not compose.** `get_url` defaults to `force: false` and
  skips entirely when `dest` already exists. Downloading onto a path that `tempfile` just
  created means nothing is fetched, the task reports `ok` rather than `changed`, and an
  empty `0600` file is left to execute. Use a temp *directory* and download to a new name
  inside it. The rustup installer then runs through `sh`, so a machine that mounts `/tmp`
  noexec still works.
- **`unarchive` needs its destination to already exist**, so the per-family font
  directories are created first. That then breaks the obvious `creates:` guard, since the
  directory now always exists and the fonts would never install again. The archives carry
  no version marker, so a following task writes `.nerd-fonts-<version>` and the guard looks
  for that. Putting the version in the stamp's *name* is what makes bumping
  `nerd_fonts_version` pull the new release.
- **`unarchive`'s `mode:` applies to the destination path**, not to the extracted files, so
  `mode: "0644"` would have left the font directories unreadable to anyone but root.
- **`copy` does not create parent directories** the way the `install -D` in the notebook
  did. `/usr/share/wayland-sessions` is the one destination nothing else provides: the other
  three come from systemd and xdg-desktop-portal, and niri's own .deb ships this one.

### Install the binary last, so the guard cannot lie

`niri --version` is the idempotency guard, so the binaries are installed *after* the
resource files. The other order looked fine until a failure in between left a machine where
niri reported 26.04, half the resource files were missing, and every later run skipped the
whole block because the guard was satisfied. Same reason xwayland-satellite's version stamp
is written after its binary.

xwayland-satellite has no version flag at all, incidentally: `--version` panics with
"Unrecognized argument". Hence the stamp file at
`/usr/local/share/xwayland-satellite-version`.

### /usr, not /usr/local, for the binaries

Upstream's manual-installation table says `/usr/local`, and the notebook deliberately
ignores it. The layout mirrors niri's own .deb and .rpm packaging, so the resource files
are used verbatim: `niri.service`'s bare `ExecStart=niri` resolves via `/usr/bin` on
systemd's user PATH. The fonts are the exception and go to `/usr/local/share/fonts`, since
they are not part of any package's layout, only system-wide instead of the
`~/.local/share/fonts` that getnf uses so a greeter and other users get them too.

### Google Chrome configures its own apt source

The `google-chrome-stable` postinst rewrites
`/etc/apt/sources.list.d/google-chrome.sources` itself, stamped "THIS FILE IS AUTOMATICALLY
CONFIGURED". So the playbook writes the same path, in the same deb822 format, with the same
`chrome-stable/deb` URI and `/usr/share/keyrings/google-chrome.gpg` keyring that Google
uses. Writing the older `google-chrome.list` instead leaves two sources for the same suite
once Chrome has updated itself once.

The consequence is one unavoidable `changed` on the *second* run: the first run writes the
file, the postinst rewrites it during install, and the second run puts it back. From the
third run on it is stable, and the postinst sets `repo_add_once="false"` in
`/etc/default/google-chrome` so it does not keep re-adding.

### No systemctl --user here

`niri-build.sh` ends with `systemctl --user daemon-reload`. That is right for a script run
from inside a desktop session and wrong for this playbook, in two ways.

It fails during a headless bootstrap. The desktop packages pull in `dbus-user-session`, but
an ssh session that was opened *before* that package existed never gets a user bus, so
`systemctl --user` in the same run dies with "Failed to connect to user scope bus via local
transport". A later login works fine. That is unavoidable on the very machine state this
playbook targets.

It is also unnecessary. The units live in `/usr/lib/systemd/user`, and a fresh login reads
them; you have to log out and back in to start the new niri anyway. Enabling waybar is a
no-op too: on a fresh trixie with waybar installed and nothing else done,
`systemctl --user show waybar.service` already reports `UnitFileState=enabled`, with no
symlink under `~/.config/systemd/user` and none shipped by the package. Same on a working
machine. Confirmed by running it: a first niri session on a machine this playbook set up
brings waybar up from `waybar.service` on its own, `enabled; preset: enabled`.

That is also why niri's **default** config gives you two bars. It carries a
`spawn-at-startup "waybar"` line, which starts a second one alongside the unit. The config
in the dotfiles deletes that line deliberately, and says so in a comment. Nothing to fix
here; it only shows up on a machine with no dotfiles stowed, such as the test VM.

### swaybg and the input group, found by running the real configs

Two packages that no dependency chain and no reading of `config.kdl` would have turned up.
Both came out of running the dotfiles' niri, waybar and kitty configs on the test VM.

`swaybg` is the Wayland wallpaper daemon. Nothing in `config.kdl` names it: the startup
line is `spawn-sh-at-startup "wal -ei ~/Wallpapers/LOTR/LOTR-ShallNotPass.jpg"`, and pywal
shells out to whichever setter it finds. Without swaybg the desktop simply comes up with
no wallpaper, and pywal still prints "Set the new wallpaper", so the log is no help. On a
working machine there is a `swaybg -m fill -i ~/Wallpapers/...` process to point at, which
is how it was found.

The `input` group is what waybar's `keyboard-state` module needs. It reads the Caps and Num
LEDs straight off `/dev/input/event*`, and without the group it logs
`Failed to find keyboard device: EACCES` and disables just that module, so the bar looks
fine at a glance. niri does not need the group; logind hands it the devices through
libseat. Membership is read at login, so the playbook's `usermod` takes effect on the next
one, and restarting `waybar.service` in the running session is not enough, the user manager
keeps the group set it started with.

### waybar from source, and why it does not replace the package

trixie ships waybar 0.12.0 (February 2025) and will not move. 0.15.0 (February 2026) is in
sid and forky, but there is no trixie-backports build, so the only route is source. In
between sit 528 commits, and the ones that matter are all in modules the bar actually uses:
a memory leak in the continuous-script path (`custom/notification` runs `swaync-client -swb`
through exactly that), the tray gaining `load_symbolic` icons and losing three menu bugs,
`battery` updating on plug and unplug again, `network` learning rfkill state and getting its
frequency unit right, and `temperature` finally dropping the `critical` class once things
cool down. `keyboard-state`, `niri/window` and `power-profiles-daemon` got nothing: the
first was not touched at all, and the other two only by the treewide clang-format sweep and
a comment typo.

The `waybar` apt package stays installed. It is not there for the binary, which
`/usr/local/bin/waybar` shadows on PATH, but for two other things: its dependency closure,
which saves this playbook from naming waybar's entire runtime library set and keeping it in
step with upstream, and a working fallback bar on a machine where the build was skipped or
failed. Nothing in the source build collides with a path dpkg owns.

### Two meson options that are not defaults, and one that is a trap

Every optional feature in `meson_options.txt` is `auto`, so **the -dev packages installed
are what decides which modules get compiled in**. That is why the build-dep list is Debian's
own `Build-Depends` for 0.15.0-1 minus the entries for modules the config does not use
(mpd, jack, sndio, gps, cava, pipewire, mpris, upower, wireplumber). Two of them are not
obvious: `libinput-dev` is named for `keyboard-state`, which needs libevdev, and it also
brings `libudev-dev` for `backlight`, both as hard Depends. `libxkbregistry-dev` is the one
dependency in `meson.build` with no feature option at all.

`-Drfkill=enabled` is needed because that option's guard is `get_option('rfkill').enabled()`
rather than `.allowed()`. A feature option left at `auto` is not `enabled()`, so the default
silently compiles rfkill out and the network module loses its rfkill state. Debian's
`debian/rules` passes exactly this one override and nothing else.

`-Dsystemd=disabled` is the trap. `--prefix=/usr/local` does not contain the unit file:
`meson.build` reads `systemduserunitdir` out of `systemd.pc`, which is the absolute
`/usr/lib/systemd/user`, so a plain build overwrites the file dpkg owns and the next
`apt upgrade` quietly puts 0.12.0's unit back. Disabling the option skips only that install
step, since `systemd_failed_units.cpp` and `-DHAVE_SYSTEMD_MONITOR` are gated on `is_linux`
and the dependency is never linked against. The playbook writes the unit itself, into
`/usr/local/lib/systemd/user`, which `systemd-analyze --user unit-paths` lists ahead of
`/usr/lib/systemd/user`, so it shadows the packaged one rather than replacing it. Enablement
is by unit name, so `waybar.service` stays enabled through the package's preset either way.

The unit is `resources/waybar.service.in` with `@prefix@` filled in, which is all the
skipped step would have done. `ExecStart` is the only line the prefix touches.

### The wallpaper chain belongs to the dotfiles, not here

`wal` itself is not installed by this playbook and should not be. The full chain is pywal16
(a `uv tool install pywal16`, symlinked at `~/.local/bin/wal`), `imagemagick` for its
default `wal` backend, and the `wallpapers` stow package for the image the config names.
That is three things that only make sense once the dotfiles are cloned and stowed, so they
belong to the dotfiles playbook that does not exist yet. `swaybg` is different, and is
here: it is a desktop component any wallpaper approach needs, pywal or not.

Without imagemagick, `wal` fails with "Imagemagick wasn't found on your system" and writes
nothing. That matters more than it sounds, because waybar's `style.css` opens with
`@import "~/.cache/wal/colors-waybar.css"` and uses `@foreground` and `@color1` from it. A
missing colour file is a hard parse error, so waybar exits 1, and systemd gives up after
five restarts with "Start request repeated too quickly". A desktop with no bar at all,
from one absent font-and-image utility.

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
