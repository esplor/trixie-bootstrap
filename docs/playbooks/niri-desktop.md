# niri-desktop.yml

niri is not packaged in trixie at all (`apt-cache policy niri` comes back empty), and
neither is xwayland-satellite, so both are built from source the way `~/code/desktop`'s
`niri-build.sh` and `xwayland-satellite-build.sh` did it by hand. Configuration stays out
of it: `~/.config/{niri,waybar,kitty}` are stow symlinks into `~/.dotfiles`, so this
playbook installs software and stops there.

Everything below was established by running it cold in the VM, not by reading the notebook
scripts, which turned out to be wrong in both directions.

## Every dependency is named here, even the ones another playbook installs

`build-essential`, `ca-certificates`, `curl` and `git` are already installed by `base.yml`
and `bootstrap.sh`, and are listed here anyway. A playbook that quietly relies on another
playbook having run is a trap on the first machine where it has not, and the test VM is the
worst place to notice, because by then everything is installed.

That is a different question from relying on a package's `Depends`. `pkg-config`,
`libglib2.0-dev` and `libcairo2-dev` are hard Depends of `libpango1.0-dev`, and
`libxcb1-dev` of `libxcb-cursor-dev`, so naming them is noise. Same reasoning as
`python3-apt` pulling in `python3`: a Depends is guaranteed, a Recommends is not.

## pipewire-audio, not pipewire and wireplumber

The obvious spelling of "install audio" is `pipewire` plus `wireplumber`, and it is wrong
here for the same reason `ca-certificates` had to be named next to curl. `pipewire-pulse`
and `libspa-0.2-bluetooth` are **Recommends** of `wireplumber`, not Depends, so
`install_recommends: false` drops both.

Losing `pipewire-pulse` is the expensive one, and it is invisible until something tries to
make a sound. It is the PulseAudio server, and almost nothing speaks PipeWire natively:
waybar's `pulseaudio` module, `pavucontrol`, the browser through cubeb, and a Flatpak app
through its `--socket=pulseaudio` permission all talk the PulseAudio client API and reach
PipeWire only through that shim. Without it the machine is simply mute, while `pactl info`
on a working one reports `Server Name: PulseAudio (on PipeWire)`. Losing
`libspa-0.2-bluetooth` costs bluetooth audio in the same silent way.

`pipewire-audio` is Debian's metapackage for exactly this set, and everything in it is a
Depends, so naming the one package is guaranteed to bring `pipewire-pulse`,
`libspa-0.2-bluetooth`, `wireplumber` (hence `pipewire`, hence `wpctl` behind the volume
binds) and `pipewire-alsa`.

`pipewire-alsa` is the only piece nothing here asks for. It repoints ALSA's `default` PCM
at PipeWire, which matters for programs that talk the raw ALSA API rather than libpulse:
wine, older games, `aplay`, sox, anything pinned to `hw:0`. None of the desktop's own
software does, but it arrives with the metapackage and costs nothing.

## The build dependencies in the notebook were wrong

Upstream publishes the real lists, in `DEPS_APT` in niri's `.github/workflows/ci.yml` and
in `.github/workflows/ubuntu.dockerfile` plus the README for xwayland-satellite.

`niri-build.sh` was **missing** `clang`, `libdbus-1-dev` and `libsystemd-dev`, and nothing
else in its list pulls them in: `libudev-dev` depends only on `libcap-dev` and `libudev1`,
and none of the other `-dev` packages depends on dbus or systemd. The script worked only
because those three were already on the machine for other reasons. It also named
`pkg-config`, `libglib2.0-dev`, `libcairo2-dev` and `libxcb1-dev`, all redundant per above.

## Two prerequisites nothing else here installs

- `python3-debian`, because `deb822_repository` parses and writes `.sources` files through
  it and fails outright without it, exactly the way the apt module needs `python3-apt`. The
  module can fetch it itself via `install_python_debian`, but naming it keeps the
  dependency visible and routes it through `--no-install-recommends` like everything else.
- `fontconfig`, for `fc-cache`. Absent on a machine that has only run `bootstrap.sh`,
  `base.yml` and `neovim.yml`.

## Build in /var/tmp, never /tmp

`ansible.builtin.tempfile` defaults to `/tmp`, and `/tmp` is a tmpfs on a stock trixie. A
cargo `target/` tree built there is held in RAM: niri's is 3.8 GB and xwayland-satellite's
921 MB. On a 4 GB VM that means three OOM kills, a load average of 11, and an sshd that
stops answering mid-build. `free` gives it away with a large `shared` column, which is the
tmpfs.

Both build directories pass `path: /var/tmp`, which is the FHS home for temporary data too
large or too long-lived for `/tmp`, and is ext4 on the root filesystem. `neovim.yml` gets
away with the default only because its build tree is small.

Budget roughly 5 GB of disk. RAM is the part that bites, and `cargo_build_jobs` is what
holds it down.

## CARGO_BUILD_JOBS, because the peak is otherwise a race

cargo defaults its job count to the core count, so RAM demand scales with cores rather than
with the machine's memory. A single `rustc` on niri's lib crate peaks near 1.5 GB, which
means four cores can want 6 GB for a build that would fit in 4.

That makes the failure intermittent, and intermittent is worse than reproducible. A 2 GB,
two-core VM was OOM-killed 5m33s into the niri build:

```
Out of memory: Killed process 28231 (rustc) total-vm:2761372kB, anon-rss:1512060kB
```

The playbook reports it as a plain build failure, `rc: 101`, and only `signal: 9, SIGKILL`
at the end of cargo's output says what really happened. The same build then succeeded on
the next run from a clean tree, because the heavy crates happened not to align that time.

Both cargo tasks therefore pass `CARGO_BUILD_JOBS`, set from the `cargo_build_jobs` var at
the top of the play. At 2 the peak is roughly 3 GB whatever the core count, so the build
fits a 4 GB machine by arithmetic rather than by luck. Raise it on a machine with memory to
spare; it only costs build time.

## rustup, pinned, rather than trixie's cargo

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

## Ansible module traps, all of them found by running it

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

## Install the binary last, so the guard cannot lie

`niri --version` is the idempotency guard, so the binaries are installed *after* the
resource files. The other order looked fine until a failure in between left a machine where
niri reported 26.04, half the resource files were missing, and every later run skipped the
whole block because the guard was satisfied. Same reason xwayland-satellite's version stamp
is written after its binary.

xwayland-satellite has no version flag at all, incidentally: `--version` panics with
"Unrecognized argument". Hence the stamp file at
`/usr/local/share/xwayland-satellite-version`.

## /usr, not /usr/local, for the binaries

Upstream's manual-installation table says `/usr/local`, and the notebook deliberately
ignores it. The layout mirrors niri's own .deb and .rpm packaging, so the resource files
are used verbatim: `niri.service`'s bare `ExecStart=niri` resolves via `/usr/bin` on
systemd's user PATH. The fonts are the exception and go to `/usr/local/share/fonts`, since
they are not part of any package's layout, only system-wide instead of the
`~/.local/share/fonts` that getnf uses so a greeter and other users get them too.

## Google Chrome configures its own apt source

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

## No systemctl --user here

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

## swaybg and the input group, found by running the real configs

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

## waybar from source, and why it does not replace the package

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

## Three meson options that are not defaults, and one that is a trap

Every optional feature in `meson_options.txt` is `auto`, so **the -dev packages installed
are what decides which modules get compiled in**, but only once `--wrap-mode=nofallback`
is passed; the last section below is why. That is why the build-dep list is Debian's
own `Build-Depends` for 0.15.0-1 minus the entries for modules the config does not use
(mpd, jack, sndio, gps, cava, pipewire, mpris, wireplumber). Two of them are not obvious:
`libinput-dev` is named for `keyboard-state`, which needs libevdev, and it also brings
`libudev-dev` for `backlight`, both as hard Depends. `libxkbregistry-dev` is the one
dependency in `meson.build` with no feature option at all.

`libupower-glib-dev` is the one entry kept for a module the config does not use yet. The
`battery` module reads `/sys/class/power_supply` directly, which structurally cannot show
a bluetooth headset, a wireless mouse or a controller, because none of them appear there.
Only UPower enumerates those. Compiling the module in costs one build dependency and
decides nothing; the bar shows a peripheral battery when, and only when, the dotfiles'
waybar config grows an `upower` block.

Note what the version guard cannot see. `waybar_needs_build` compares the installed
version against `waybar_version`, so changing a build dependency or a meson option on a
machine already running 0.15.0 rebuilds nothing. Force it with
`-e '{"waybar_needs_build": true}'`, in JSON: the `key=value` form passes the string
`"true"`, and ansible-core 2.19 and later refuse a conditional that is not a real boolean.

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

`-Dtests=disabled` is the third, and it was found the hard way: the same build that
succeeds in the VM fails on a machine with a Catch2 install under `/usr/local`. The
`tests` option is `auto` like the rest, so meson enables the test targets whenever it
finds catch2 through `catch2.pc`, and then compiles a test suite this playbook never runs.
Where that install is incomplete the build dies partway through with `fatal error:
catch2/internal/catch_config_prefix_messages.hpp`, on a target whose output would have
been thrown away regardless.

The VM never saw it because a minimal trixie has no catch2 at all, which is the same class
of hole as the notebook's niri build depending on three packages that were already there.
Disabling the option outright is what makes the build depend on the named build
dependencies and nothing else.

## --wrap-mode=nofallback, or the build installs things nobody asked for

An unfound dependency does not simply disable its feature. meson falls back to a
subproject, downloads the source, builds it, and `meson install` then writes that
subproject into the prefix alongside waybar. Two got through before this was understood:

- **catch2**, which is how `/usr/local/include/catch2` and `libCatch2.a` appeared on both
  the test VM and a real machine, dated to the minute of the first waybar build. That
  install is partial, so the *second* build finds the `catch2.pc` the first one left,
  prefers it over the subproject, and dies on a header the install omitted. First run
  green, second run red, broken by its own output.
- **libcava**, which linked `libcava.so` into the binary for a module the dependency list
  deliberately excludes. `/usr/local/lib/x86_64-linux-gnu` is in `ld.so.conf.d`, but the
  build does not run `ldconfig`, so the installed waybar could not start at all:
  `error while loading shared libraries: libcava.so`.

The VM got catch2 but not cava, purely because the cava subproject needs build
dependencies a minimal trixie lacks and a developer's machine happens to have. That is the
whole argument for the flag. Without it, which modules a build produces depends on what
else is installed for unrelated reasons, which is the opposite of what this playbook is
for. With it, a dependency that is not installed disables its feature and nothing else
happens.

## pywal is installed here, the wallpaper it renders is not

This reverses an earlier decision, kept on the page because half of its reasoning still
holds. The chain is pywal16 (`uv tool install pywal16`, symlinked at `~/.local/bin/wal`),
`imagemagick` for its default backend, and the `wallpapers` stow package for the image
`config.kdl` names. The first two are here now, the third is not, and neither is anything
that clones or stows the dotfiles.

The argument for leaving all three out was that they only make sense once the dotfiles are
stowed. That holds for the image, which is useless alone, but not for pywal. This playbook
already installs `swaybg` *because* pywal shells out to it, and the configs it exists to
serve read `~/.cache/wal` in three places: niri's `include`, kitty's `include` and waybar's
`@import`, with tmux inheriting the palette a fourth time through kitty. Installing pywal's
setter and its backend while leaving pywal itself to a dotfiles playbook that does not
exist was the inconsistency. It also failed silently: the startup `wal -ei ...` died with
command not found, so there was no wallpaper and no `~/.cache/wal` at all.

`imagemagick` is named here rather than leaned on from `neovim.yml`, which installs it too,
per the rule at the top of this page. Without it `wal` fails with "Imagemagick wasn't found
on your system" and writes nothing. That matters more than it sounds, because waybar's
`style.css` opens with `@import "~/.cache/wal/colors-waybar.css"` and uses `@foreground`
and `@color1` from it. A missing colour file is a hard parse error, so waybar exits 1, and
systemd gives up after five restarts with "Start request repeated too quickly". A desktop
with no bar at all, from one absent font-and-image utility.

Only waybar dies. niri's include is `optional=true` and kitty ignores an include it cannot
read, so both keep the fallback colors compiled into their configs.

## tmux is here rather than in base.yml

An odd home for a terminal multiplexer, and it is the colors that put it there. The stowed
`tmux.conf` names palette indices, `colour0` to `colour15`, instead of hex, so the bar
takes whatever the attached terminal holds in those slots, and on this desktop that is
kitty carrying pywal's palette.

The coupling is softer than it sounds. Nothing breaks without the desktop: under any other
terminal tmux falls back to that terminal's own sixteen colors and the bar stays readable.
What it loses is the wallpaper. The parts that do need a capable terminal, the `─` rule on
the status bar's upper row and the `RGB` override, want UTF-8 and truecolor rather than
kitty specifically. `screen` stays in `base.yml`, where it is a server requirement.
