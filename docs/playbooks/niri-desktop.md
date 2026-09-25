# niri-desktop.yml

niri is not packaged in trixie at all (`apt-cache policy niri` comes back empty), and
neither is xwayland-satellite, so both are built from source the way `~/code/desktop`'s
`niri-build.sh` and `xwayland-satellite-build.sh` did it by hand, and the noctalia shell
on top of them. Configuration stays out of it: `~/.config/{niri,noctalia,kitty}` are stow
symlinks into `~/.dotfiles`, so this playbook installs software and stops there.

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
`pavucontrol`, the browser through cubeb, and a Flatpak app through its
`--socket=pulseaudio` permission all talk the PulseAudio client API and reach PipeWire
only through that shim. Without it the machine is simply mute, while `pactl info`
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

The metapackage does not cover everything. `rtkit` is a **Recommends** of `pipewire-bin`,
one level further down, so it is dropped too, and nothing fails loudly: pipewire,
pipewire-pulse and wireplumber each log
`RTKit error: org.freedesktop.DBus.Error.ServiceUnknown` at login and fall back to normal
scheduling priority. Audio works until the machine is
under load, and then it crackles. Found in the VM's journal, so it is named explicitly.

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

Budget roughly 5 GB of disk. RAM is the part that bites, and `build_jobs` is what
holds it down.

## One build job per 2 GB, because the peak is otherwise a race

cargo defaults its job count to the core count, and ninja to the core count plus two, so RAM
demand scales with cores rather than with the machine's memory. A single `rustc` on niri's
lib crate peaks near 2 GB, which means four cores can want 8 GB for a build that would fit
in 4.

That makes the failure intermittent, and intermittent is worse than reproducible. A 2 GB,
two-core VM was OOM-killed 5m33s into the niri build:

```
Out of memory: Killed process 28231 (rustc) total-vm:2761372kB, anon-rss:1512060kB
```

The playbook reports it as a plain build failure, `rc: 101`, and only `signal: 9, SIGKILL`
at the end of cargo's output says what really happened. The same build then succeeded on
the next run from a clean tree, because the heavy crates happened not to align that time.

Every build therefore takes its job count from the `build_jobs` var at the top of the
play: `CARGO_BUILD_JOBS` for the two cargo builds, `meson compile -j` for noctalia. It is
derived rather than fixed: one job per 2 GB of `ansible_facts['memtotal_mb']`, clamped
between 1 and `ansible_facts['processor_vcpus']`, so the build fits by arithmetic rather
than by luck and still uses a big machine. A 4 GB VM gets 1 job, 8 GB gets 3, and a 16 GB,
16-thread laptop gets 7.

The 2 GB is measured, not guessed. With 2 jobs on an 8 GB VM, used memory peaked at
2.4 GB for niri (one `rustc` at 2.0 GB of it) and 2.3 GB for noctalia (largest `cc1plus`
920 MB). The waybar build this playbook used to carry was left at ninja's default, and
there 6 jobs peaked at 3.8 GB, most of a 4 GB machine, which is what made the cap apply to
every build rather than only cargo's.

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

## /usr/local for the binaries, /usr for the resource files

niri, niri-session and xwayland-satellite go to `/usr/local/bin`, as upstream's
manual-installation table says, next to the meson-installed noctalia. The resource files
stay where niri's own .deb puts them (`/usr/share/wayland-sessions`,
`/usr/lib/systemd/user`, `/usr/share/xdg-desktop-portal`), since that is where display
managers, systemd and the portal look. They are used verbatim: none holds an absolute
path, and `niri.service`'s bare `ExecStart=niri` and `niri.desktop`'s `Exec=niri-session`
resolve via `/usr/local/bin`, which systemd's user PATH lists ahead of `/usr/bin`.

The niri guard runs `/usr/local/bin/niri --version` by absolute path, like noctalia's, so
no other niri on root's PATH can answer for the build.

An earlier version of this playbook installed the binaries to `/usr/bin`. Its
xwayland-satellite stamp would still match, so the guard also checks that
`/usr/local/bin/xwayland-satellite` exists. The old `/usr/bin` copies are not removed;
`/usr/local/bin` shadows them, but delete them by hand on a machine that ran it.

The fonts go to `/usr/local/share/fonts` too, system-wide instead of the
`~/.local/share/fonts` that getnf uses, so a greeter and other users get them.

## Google Chrome configures its own apt source

The `google-chrome-stable` postinst rewrites
`/etc/apt/sources.list.d/google-chrome.sources` itself, stamped "THIS FILE IS AUTOMATICALLY
CONFIGURED". So the playbook writes the same path, in the same deb822 format, with the same
`chrome-stable/deb` URI and `/usr/share/keyrings/google-chrome.gpg` keyring that Google
uses. Writing the older `google-chrome.list` instead leaves two sources for the same suite
once Chrome has updated itself once.

Matching Google's format is not enough to stop the two from fighting over the file, and it
is not the once-only skirmish it looks like. `repo_add_once="false"`, which the postinst
writes into `/etc/default/google-chrome`, looks like the thing that should end it, but
`install_deb822_sources` never reaches that gate:

```sh
if [ -f "$SOURCES_FILE" ]; then
    # The new .sources file already exists. Recreate it in case it got disabled
    # during a dist upgrade.
    SHOULD_INSTALL_SOURCES=1
fi
```

The file always exists when the postinst runs, because apt cannot install the package
until the repository is there, so the postinst always recreates it and the next playbook
run puts it back. That is one spurious `changed` after every Chrome upgrade, forever, not
once. The two versions describe the same repository and differ only in field order, the
`X-Repolib-Name` value (`google-chrome` against `Google Chrome`), an `Enabled: yes` line
and a three-line header.

So the task is gated on Chrome not being installed. It exists only to bootstrap the first
`apt install`; after that the file belongs to Chrome, which its own header states outright.
`dpkg-query -W -f=${Status}` prints `install ok installed` once Chrome is in, and exits 1
with empty stdout when it is not, so `failed_when: false` and a `not in` test cover both.
A removed-but-not-purged Chrome reports `deinstall ok config-files`, which re-adds the
repository, and that is what a reinstall needs.

The trade: delete that file on a machine that already has Chrome and nothing puts it back,
because the playbook now skips and Chrome's own header says "This file will not be
recreated if removed".

`/etc/cron.daily/google-chrome` carries the same repo-writing logic, gated on
`repo_add_once` and so dormant, but `/etc/default/google-chrome` also holds
`repo_reenable_on_distupgrade="true"`, which re-arms it across a release upgrade.

## No systemctl --user here

`niri-build.sh` ends with `systemctl --user daemon-reload`. That is right for a script run
from inside a desktop session and wrong for this playbook, in two ways.

It fails during a headless bootstrap. The desktop packages pull in `dbus-user-session`, but
an ssh session that was opened *before* that package existed never gets a user bus, so
`systemctl --user` in the same run dies with "Failed to connect to user scope bus via local
transport". A later login works fine. That is unavoidable on the very machine state this
playbook targets.

It is also unnecessary. The units live in `/usr/lib/systemd/user`, and a fresh login reads
them; you have to log out and back in to start the new niri anyway.

niri's **default** config carries a `spawn-at-startup "waybar"` line. waybar is not
installed any more, so on a machine with no dotfiles stowed, such as the test VM, that line
just fails quietly at login. The dotfiles' config starts noctalia instead.

## noctalia from source, pinned to a tag

noctalia v5 is a native Wayland shell (bar, launcher, notifications, lock screen, OSDs) in
C++23 on Meson, with no Qt or GTK. trixie does not package it. Upstream points Debian users
at an APT repository with a trixie suite, but that repository is community-maintained,
signed by an individual's key, and serves whatever the latest release is. Building the tag
named in `noctalia_version` keeps the version a decision made in this repo, the same as
niri.

Every package in upstream's Debian list exists on trixie, but the list as a whole does not
install. It names `libcurl4-openssl-dev`, and trixie's `libqalculate-dev` Depends on
`libcurl4-gnutls-dev`, which Conflicts with it, so apt rejects the entire set with "held
broken packages". `apt-cache policy` on each name one at a time says nothing is wrong;
only installing them together shows it. The playbook names the gnutls flavour instead,
which provides the same `libcurl` pkg-config module that `meson.build` asks for.

The libraries are not the whole story, because `meson.build` also reads protocol XML out of
`wayland-protocols`' `pkgdatadir`, and one of those files is newer than trixie.
`staging/ext-background-effect/ext-background-effect-v1.xml` arrived in wayland-protocols
1.45; trixie has 1.44, so configure fails after every dependency has been found. It is the
only file missing: every other system protocol noctalia generates code from is in 1.44.
trixie-backports carries 1.47, so the playbook adds that suite and installs this one
package from it with `state: latest`, which also moves a machine already on 1.44. The
suite comes from `files/etc/apt/sources.list.d/debian.sources`, the same file `base.yml`
installs (see its page). This playbook installs it too rather than relying on `base.yml`
having run, for the reason in the first section: without it apt does not know the suite. A
backports suite is `NotAutomatic`, so adding it changes nothing else on the machine, and
the package is only XML. niri and xwayland-satellite do not read it at all; their protocol
definitions come from Rust crates.

The cache refresh is a separate task, and has to be. `ansible.builtin.apt` sets
`APT::Default-Release` before it runs its own `update_cache`, so a single task with both
fails on exactly the run that adds the source: `E:The value 'trixie-backports' is invalid
for APT::Default-Release as such a release is not available in the sources`. The suite is
not in `/var/lib/apt/lists` yet, and the update that would put it there is the step the
error prevents.

Two more things are worth checking first because packagers hit them: `libstb-dev` must ship
`stb/stb_image_resize2.h` (trixie's `0.0~git20241109` does), and meson needs
`wireplumber-0.5`, which trixie has. `g++` 14 clears the GCC 13 floor for C++23.

The configure is PACKAGING.md's rather than the justfile's. `just configure release` adds
`-Db_lto=true`, which moves a large part of the work into the final link and raises its
memory peak, on a build that has to fit the same small VM as niri. `meson compile` gets
`-j` from `build_jobs` because ninja's default is the core count plus two, the same race as
cargo's. `-Dtests=disabled` is stated rather than left to `auto`, which means off for a
release build only because upstream says so today. A feature option at `auto` decides
itself from whatever it finds installed, and the waybar build this playbook used to carry
was broken exactly that way, compiling a test suite against a partial Catch2 left in
`/usr/local`. `-Djemalloc=enabled` turns upstream's `auto` into a hard requirement, so a
missing `libjemalloc-dev` fails the build instead of quietly producing a binary without
it. There is no `subprojects/` directory, so meson has nothing to fall back to and
download; the vendored code lives in `third_party/`.

The prefix is compiled into the binary as the asset lookup path, and the `assets/` tree is
required at runtime, so the install is `meson install` from the configured build, never a
copy of the binary. `--no-rebuild` keeps the root-owned install step from recompiling
anything as root.

What the playbook deliberately does not do is start it. No systemd unit ships and none is
written; the dotfiles' niri config has `spawn-at-startup "noctalia"`. On niri, noctalia
registers `org.freedesktop.Notifications` and `org.kde.StatusNotifierWatcher`, so nothing
else in the session may hold either name. That is one of the reasons the packages below are
gone rather than merely unused.

## What noctalia replaced, and what it did not

noctalia is one process covering what used to be a stack of small tools, so the playbook
dropped each package it made redundant rather than leaving them installed and unused:

| Removed | Replaced by noctalia's |
|---|---|
| `waybar`, its source build and build dependencies | bar |
| `sway-notification-center` | notifications and history |
| `fuzzel`, `wofi` | launcher |
| `swaylock` | lock screen |
| `swaybg`, pywal16, `imagemagick` | wallpaper, palette and app templates |
| `network-manager-applet` | network panel and NetworkManager secret agent |
| `ukui-polkit` | polkit agent |
| `playerctl` | `noctalia msg media ...` |

The `input` group went with waybar: its `keyboard-state` module read the Caps and Num LEDs
off `/dev/input`, and noctalia never opens an evdev node. Machines set up before this keep
the membership, which is harmless.

Three things stay, each for something noctalia cannot do. `pavucontrol` switches a card's
profile, Bluetooth A2DP against headset mode or HDMI output; noctalia moves streams between
outputs and sets volumes, but has no call to change a profile. `brightnessctl` backs the
dotfiles' `bl-*` shell functions, even though the brightness keys now go through noctalia.
And the secret agent only answers Wi-Fi requests, so a VPN that asks for a password at
connect time needs `nmcli --ask connection up <name>` or `nmtui`, both of which come with
`network-manager` itself.

Two audio tools were never in the list and are here now for the same reason. EasyEffects
does the processing, equalizer, crossfeed and the rest, and noctalia does none: it can
switch EasyEffects presets, no more. Its effects are LV2 plugins that are only
**Recommends**, the `pipewire-pulse` trap again, so `lsp-plugins-lv2`, `mda-lv2`,
`zam-plugins` and `calf-plugins` are named. Calf is listed there only as an alternative to
LSP, but it is the one that provides the bass enhancer. Without them the effects show as not installed, and a preset that
uses one skips it without saying so. Helvum is a patchbay, for links noctalia cannot make:
noctalia moves a stream to one output, Helvum can send it to several.

Removing a package from this list does not remove it from a machine that already has it.
`apt autoremove` will not touch it either, because it was installed by name.

## tmux is here rather than in base.yml

An odd home for a terminal multiplexer, and it is the colors that put it there. The stowed
`tmux.conf` names palette indices, `colour0` to `colour15`, instead of hex, so the bar
takes whatever the attached terminal holds in those slots, and on this desktop that is
kitty carrying noctalia's palette.

The coupling is softer than it sounds. Nothing breaks without the desktop: under any other
terminal tmux falls back to that terminal's own sixteen colors and the bar stays readable.
What it loses is the wallpaper. The parts that do need a capable terminal, the `─` rule on
the status bar's upper row and the `RGB` override, want UTF-8 and truecolor rather than
kitty specifically. `screen` stays in `base.yml`, where it is a server requirement.
