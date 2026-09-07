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

Add `-K` when sudo wants a password. The "no inventory was parsed" warning is expected: the
only host is the implicit localhost.
