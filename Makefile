# Names for the commands that are too long to want to retype. Not a build system: every
# recipe here is a one-line alias for something the README already spells out.

.PHONY: docs-serve

# --group dev because default-groups is empty in pyproject.toml, so the dev tooling is
# opt-in and a plain "uv run" would not see zensical.
docs-serve:
	uv run --group dev zensical serve
