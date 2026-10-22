# Toolkit host setup

Developer host setup for OpenDAP: the tools, toolchains and checks every contributor installs. Everything runs locally; there is no CI.

Part of the [OpenDAP](https://github.com/opendap-project) Developer Toolkit, which lives in the workspace under `public/toolkit/` as one repository per tool domain.

Tools every OpenDAP contributor installs on their machine. Everything runs locally; there is no CI.

Officially supported: UNIX / POSIX systems. Tested on macOS only (TK-010, TK-011). Windows is not supported.

```sh
setup.sh
```

The script is safe to run again. It installs the Homebrew packages in [`Brewfile`](Brewfile), enables Git LFS, adds the Rust targets, installs the cargo tools and Interactive HTML BOM (inside KiCad's Python), and checks the design applications.

## Installed

| Area | Tools |
|---|---|
| Design | KiCad 10, FreeCAD 1.1, Blender 5.2 (official installers) |
| Fab outputs | `kicad-cli` (bundled with KiCad), Interactive HTML BOM |
| Repository hygiene | pre-commit, REUSE, Git LFS, gh, jq, yq |
| Simulation | ngspice; Python studies use `uv` with their own `pyproject.toml` |
| Firmware | rustup targets for aarch64 Linux (glibc, musl), Cortex-M0+, Cortex-M33 and RISC-V; probe-rs, picotool, dfu-util, OpenOCD, tio, sigrok-cli |
| Rust | cargo-binstall, cargo-nextest, cargo-deny |
| Emulation | QEMU |

## Installed later, when the phase needs them

Recommendations from [`docs/research/`](docs/research/), not installed yet:

- **Layout:** openEMS (built from source), gerber2ems, Elmer FEM, scikit-rf and SignalIntegrity (per study).
- **Mechanical prototyping:** FreeCAD addons KiCad StepUp, SheetMetal and Fasteners (Addon Manager); CalculiX; slicers for the DIY kit.
- **Once the SoC is chosen:** uuu (i.MX) or rockusb (Rockchip), bmaptool, the OpenDAP OS build container.
- **FPGA HATs:** OSS CAD Suite.
- **Bring-up:** PulseView, ngscopeclient, Tracy, Arm GNU Toolchain.
- **Production:** test frameworks and fixtures.

## Layout

- `setup.sh` — installs and checks everything; safe to run again
- `Brewfile` — Homebrew packages
- `docs/` — requirements and research

## License

This repository follows the [REUSE](https://reuse.software) layout: license texts live in `LICENSES/` and `REUSE.toml` maps each path to its license.

- Default: **GNU GPL v3.0 or later** (`GPL-3.0-or-later`)
- Markdown files and `docs/`: **Creative Commons Attribution-ShareAlike 4.0** (`CC-BY-SA-4.0`)

Copyright © 2026 The OpenDAP Project.
