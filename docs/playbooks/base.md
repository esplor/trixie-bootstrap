# base.yml

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

`screen` is in the set as a server requirement rather than a local preference. `tmux` is
not here despite being its obvious neighbour, see `niri-desktop.yml` for why.

## One debian.sources instead of sources.list

`files/etc/apt/sources.list.d/debian.sources` holds every Debian suite in deb822 format:
`trixie`, `trixie-updates` and `trixie-backports` from `deb.debian.org`, and
`trixie-security` from `security.debian.org`, all with `main contrib non-free
non-free-firmware`, which is what the installer writes. The installer's one-line
`/etc/apt/sources.list` is moved to `sources.list.bak`, so each suite is listed once. Moved
rather than deleted, the way `apt modernize-sources` does it, so a local mirror or an extra
line on some machine is still there to copy back.

It is a file rather than a run of `apt modernize-sources` because that command converts
whatever the machine happens to have, so its result is not in the repo, and it is a
one-shot `command` that needs guards to be idempotent. The file states the result.

The cost is that the playbook picks the mirror and the components on every machine.
Backports is in the list because `niri-desktop.yml` needs `wayland-protocols` from it and
the laptop's firmware packages came from it; a backports suite is `NotAutomatic`, so
listing it installs nothing from it. `niri-desktop.yml` installs the same file, so it
works without this playbook having run.

The cache refresh is its own task, run only when the file or the move changed, since the
install task's `cache_valid_time` would otherwise skip the update the new sources need.

## zram swap, zstd, swappiness 150

`zram-tools` gives every machine a compressed swap device in RAM at priority 100, ahead of
any disk swap. Two settings differ from the package's defaults:

- `ALGO=zstd` instead of lz4. It costs a little more CPU and compresses noticeably better:
  lz4 measured about 2.3:1 on a desktop, and zstd usually does about 3:1.
- `PERCENT=100` instead of 50. It caps how much uncompressed data the device can hold, and
  reserves nothing: the RAM is only used as pages are stored, compressed. At 3:1, a full
  device takes about a third of RAM. Fedora sizes zram to RAM (capped at 8 GB) for the
  same reason. A desktop with 16 GB had 4.3 GB in zram in normal use, with a build on top.

Both files are in `files/`: `etc/default/zramswap` and `etc/sysctl.d/99-swappiness.conf`.

The config is copied before the package is installed, so the postinst starts zramswap with
it and nothing has to restart. On a machine that already runs zramswap, the change
waits for the next boot. `systemctl restart zramswap` would apply it now, but its
`swapoff` pulls everything swapped back into RAM first, which can OOM a machine that
needs the swap. It is a conffile, and dpkg keeps a file that is already there on first
install, leaving the packaged defaults as `zramswap.dpkg-dist`. On a machine that already
has zram-tools, the copy replaces the whole file, not just the two values.

`vm.swappiness` goes from 60 to 150. It weighs swapping anonymous memory (heaps, idle
tabs) against dropping file cache (libraries, binaries), which then has to be reread from
disk. 60 assumes swap is a disk and therefore expensive; with zram, swapping is a compress
into RAM, cheaper than the reread, so values above 100 tell the kernel to prefer it. Disk
swap still sits behind zram and only fills once zram is full. It is applied by restarting
`systemd-sysctl`, because the `sysctl` binary is procps, which a minimal install lacks.

Add `-K` when sudo wants a password. The "no inventory was parsed" warning is expected: the
only host is the implicit localhost.
