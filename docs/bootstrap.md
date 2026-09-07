# bootstrap.sh


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
