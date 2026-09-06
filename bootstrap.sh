#!/usr/bin/env sh

# Description: Bring a fresh Debian 13 (trixie) install to the point where uv is
# available. Everything built here later runs through uv.
#
# Usage: ./bootstrap.sh

# Abort on the first failing command or pipeline stage (pipefail is not POSIX,
# so probe it in a subshell: a failed "set -o" aborts dash even with "|| true")
set -e
# shellcheck disable=SC3040
if (set -o pipefail) 2>/dev/null; then set -o pipefail; fi

# ANSI color codes - bold and bright for visibility
RED='\033[1;91m'    # Bold bright red
GREEN='\033[1;92m'  # Bold bright green
NC='\033[0m'        # No Color

success() { printf '%b=== %s ===%b\n' "$GREEN" "$1" "$NC"; }
alert() { printf '%b=== %s ===%b\n' "$RED" "$1" "$NC" >&2; }
tip() { printf '%b*** TIP! %s ***%b\n' "$GREEN" "$1" "$NC"; }

# apt-get update is wanted by more than one step below, but only once per run.
apt_updated=0
apt_update_once() {
    if [ "$apt_updated" -eq 0 ]; then
        sudo apt-get update
        apt_updated=1
    fi
}

# 1. curl, the only way to fetch the uv installer on a minimal install.
#    ca-certificates is merely a Recommends of libcurl4t64, so with
#    --no-install-recommends it has to be named or curl cannot verify TLS.
if ! command -v curl >/dev/null 2>&1; then
    alert "curl not found, installing curl and ca-certificates"
    apt_update_once
    sudo apt-get install -y --no-install-recommends curl ca-certificates
fi
success "curl: $(curl --version | head -n 1)"

# 2. python3 plus the apt bindings. uv is pinned to the system interpreter
#    (python-preference in pyproject.toml), and ansible's apt module needs python3-apt
#    or it auto-installs it mid-play and fails outright under --check.
#    Probe /usr/bin/python3 by name, since that is the interpreter ansible looks in
#    and the only one the bindings are built for, whatever "python3" is on PATH.
if ! /usr/bin/python3 -c 'import apt_pkg' >/dev/null 2>&1; then
    alert "python3 with apt bindings not found, installing python3-apt"
    apt_update_once
    # python3 is a Depends of python3-apt, so apt pulls the interpreter in itself.
    sudo apt-get install -y --no-install-recommends python3-apt
fi
success "python3: $(/usr/bin/python3 --version)"

# 3. uv itself.
uv_fresh=0
if ! command -v uv >/dev/null 2>&1; then
    alert "uv not found, installing via the Astral installer"
    # UV_NO_MODIFY_PATH: shell rc files belong to the dotfiles, not to this script.
    curl -fsSL https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh
    uv_fresh=1
    # With UV_NO_MODIFY_PATH the installer writes no env file and no rc line at all,
    # so put uv on PATH by hand for the rest of this script.
    PATH="$HOME/.local/bin:$PATH"
    export PATH
fi
success "uv: $(uv --version)"

# A child process cannot put uv on the PATH of the shell that started it, and Debian's
# ~/.profile only adds ~/.local/bin when the directory already exists at login, which it
# did not before this run. So the next login is enough; this session needs a nudge.
if [ "$uv_fresh" -eq 1 ]; then
    tip "uv lives in \$HOME/.local/bin. Log out and back in, or run: . \$HOME/.profile"
fi
