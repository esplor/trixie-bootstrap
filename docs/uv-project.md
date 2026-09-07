# The uv project

`ansible-core` is a regular dependency, `ansible-lint` a dev one. Both `uv sync` and
`uv run` install the default groups, so a plain `uv run` would quietly reinstall the lint
tooling that a `--no-dev` sync just left out. Rather than repeat `--no-dev` on every
command, `default-groups = []` makes dev opt-in: plain `uv sync` and `uv run` stay lean,
and linting is `uv run --group dev ansible-lint base.yml` when you want it.

`python-preference = "only-system"` pins uv to trixie's own Python 3.13, so no machine ends
up with a second interpreter it did not ask for. There is no `.python-version`, since
pinning one invites uv to fetch a matching build.
