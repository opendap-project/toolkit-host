# Toolkit host setup

Developer host setup for OpenDAP: the tools, toolchains and checks every contributor installs. Everything runs locally; there is no CI.

Part of [OpenDAP](https://github.com/opendap-project). This repository is open source.

## Working here

- Write everything in English: code, docs, commit messages.
- Record only information the maintainers confirmed. Do not infer specs, numbers or wording.
- Project context is in `docs/`: requirements in `docs/requirements/`. Read them before changing anything; update them with the `/opendap:requirement` and `/opendap:adr` skills.
- Licensing follows REUSE (`REUSE.toml`, `LICENSES/`). After adding files or folders, run the `/opendap:license-check` skill.
- The toolkit is one repository per tool domain under `public/toolkit/` (`host`, `image`, `hardware`, `verify`, `hooks`); the `opendap` CLI is user-side and lives in `cli`, outside the toolkit. Use another toolkit repository through its documented interface, not its internals.
