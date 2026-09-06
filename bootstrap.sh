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

# 1. curl, the only way to fetch the uv installer on a minimal install.
#    ca-certificates is merely a Recommends of libcurl4t64, so with
#    --no-install-recommends it has to be named or curl cannot verify TLS.
if ! command -v curl >/dev/null 2>&1; then
    alert "curl not found, installing curl and ca-certificates"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends curl ca-certificates
fi
success "curl: $(curl --version | head -n 1)"

# 2. uv itself.
uv_fresh=0
if ! command -v uv >/dev/null 2>&1; then
    alert "uv not found, installing via the Astral installer"
    # UV_NO_MODIFY_PATH: shell rc files belong to the dotfiles, not to this script.
    curl -fsSL https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh
    uv_fresh=1
    # The installer only writes the env file, so put uv on PATH for this shell too.
    if [ -f "$HOME/.local/bin/env" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.local/bin/env"
    else
        PATH="$HOME/.local/bin:$PATH"
        export PATH
    fi
fi
success "uv: $(uv --version)"

if [ "$uv_fresh" -eq 1 ]; then
    tip "uv lives in \$HOME/.local/bin; make sure that is on PATH in new shells"
fi
