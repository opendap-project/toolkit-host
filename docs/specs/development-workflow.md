# Development workflow

- **Status:** Draft, 2026-10-23. Decided by Claude under the maintainers' delegation, after they asked for development to happen on the host, with VMs as the runtime, and for the whole process to be defined. Cross-repository changes: [RFC 0006](https://github.com/opendap-project/rfcs/blob/main/text/0006-development-workflow.md), [RFC 0007](https://github.com/opendap-project/rfcs/blob/main/text/0007-virtual-devices.md) (virtual devices) and [RFC 0008](https://github.com/opendap-project/rfcs/blob/main/text/0008-repository-restructure.md) (repositories by audience, `odap` names).
- **Builds on:**
  - the [software and firmware toolchain research](../research/2026-10-software-firmware-toolchain.md);
  - TK-001, TK-010 and TK-011 (host tools, UNIX only, tested on macOS);
  - Blackbird OS OS-009, OS-016, OS-018 and OS-019 (run, control and automate the system on the host);
  - system ADR 0001, ADR 0002, ADR 0006, ADR 0008, ADR 0011, ADR 0012 and ADR 0013 (Rust, the shell and session, Slint, the dependency set, package layers, hardware descriptions).
- **Verified** on macOS 27 (Apple silicon), 2026-10-23: every command in §4 and §5, with the results in §9.

## 1. Summary

1. **Code is written, built and tested on the developer host.** Linux virtual machines never compile OpenDAP software.
2. **The build VM builds images and the sysroot, nothing else.** It runs mkosi, because mkosi needs Linux; toolkit-image's `odap-image` drives it.
3. **Virtual devices and the T1 are runtimes.** Software reaches them as development system extensions (package layer L3 of ADR 0011), without rebuilding the image.
4. **The fastest loop that can show a change is the one to use:** domain and core crates natively, the product UI in a window, the virtual device for the Linux device stack, the T1 for the hardware.
5. **Tools are one task each, named by their domain** (`odap-image`, `odap-vdev`…), find other repositories through the workspace's `repos.tsv`, and pass other repositories' content to builds as inputs, never as paths written into a definition.

## 2. Roles

| Machine | Does | Never does |
|---|---|---|
| **Host** (macOS, or Linux) | Edit, `cargo check`, `cargo test`, `cargo clippy`; run the product UI natively; cross-build for aarch64 (`odap-cross`); deploy (`odap-deploy`); run and drive virtual devices (`odap-vdev`); every repository check (pre-commit, REUSE) | Hold anything another machine needs in order to build |
| **Build VM** (Lima, toolkit-image `vm/build-vm.yaml`, the workspace and `~/.local/share/opendap` mounted) | `mkosi` builds: images (`qemu`, `oci`, later device profiles) and the `sysroot` profile | Compile OpenDAP software; hold a Rust toolchain; keep state that is not in the image definition |
| **Virtual devices** (QEMU, [virtual-devices](https://github.com/opendap-project/virtual-devices) `odap-vdev`) | Run Blackbird OS on a virtual model: display, touch, buttons, audio, battery, USB, microSD, LAN (VD-001) | Build anything |
| **T1** | Run Blackbird OS on the hardware | Build anything |

On a Linux host the build VM is optional: mkosi can run on the host itself. Only macOS is tested (TK-011).

## 3. Toolchain

| Piece | Pin | Where it comes from |
|---|---|---|
| Rust | `rust-toolchain.toml` in each repository: an exact version (1.99.1), `rustfmt`, `clippy`, the targets the repository builds | rustup, which reads the file |
| Cross linker | zig (0.17.0 verified) with cargo-zigbuild (0.24.0) | `Brewfile`, `setup.sh` |
| Target | `aarch64-unknown-linux-gnu.2.41`: the image's glibc (Debian trixie, libc6 2.41) | toolkit-image `odap-cross` |
| Sysroot | The image's own packages plus their `-dev` packages, built by the `sysroot` profile | toolkit-image `odap-sysroot` |
| Image builder | mkosi in the build VM | toolkit-image `odap-image` |
| Development key | One ed25519 key, host-wide in `~/.local/share/opendap/dev-ssh` | toolkit-image `odap-dev-key` |
| Emulator | QEMU with HVF on macOS; socket_vmnet for a LAN address | `Brewfile`; `bin/odap-vmnet install` |

- **Sysroot.** Linking against libinput, libseat, GBM, EGL, Wayland or ALSA needs the target's headers and libraries.
  - It is built from the image definition, so binaries link against exactly what the image ships.
  - macOS volumes are case-insensitive and Linux headers are not (`ipt_ecn.h` and `ipt_ECN.h`), so it lives in a case-sensitive APFS sparse image under `~/.cache/opendap/`, with Spotlight indexing off.
  - Rebuild it when the image's package set changes.
- **Pinning the remaining tools** (zig, cargo-zigbuild, QEMU) is open. Homebrew installs current versions today; the research's candidate is mise.

## 4. Loops

| Loop | Command | For | Takes |
|---|---|---|---|
| **Host tests** | `cargo test -p <crate>` | Domain and core crates, which are platform-agnostic (Rust crate architecture §4); adapters with fakes | Seconds |
| **UI on the host** | `cargo run -p odap-product` | Product UI: layout, tokens, type, icons, touch with the pointer, with Blackbird UI's published outputs | Seconds |
| **Virtual device** | `odap-deploy` in the Cargo workspace, then `odap-vdev screen capture / input press ROLE / input tap`, the `--window`, and `odap-vdev ssh journalctl -u odap-shell` | The shell, the boot UI, and anything that needs DRM, libinput, logind, systemd, ALSA or a board's description | Seconds to deploy; a cross-build is incremental |
| **T1** | The same extensions over SSH on the USB network link (`ODAP_DEVICE_SSH`), once the hardware exists | Timing, power, audio quality, the real panel, buttons and LED | — |
| **Image** | `odap-image build qemu`, then `odap-vdev start` | Changes to the image definition: packages, units, configuration | Minutes |

**Development extensions.** `odap-deploy` cross-builds the workspace's binaries (the default list and the units to restart are in `[workspace.metadata.odap]` of its `Cargo.toml`), stages them as `/var/lib/extensions/odap-dev-<workspace>/usr/bin/…` with `ID=_any`, merges them with `systemd-sysext refresh`, syncs the disk and restarts the units. Several workspaces deploy side by side (system and toolkit-verify today). `systemd-sysext unmerge` and removing the directories return the device to its image. Development extensions never go into images and are not how software ships (§6).

## 5. What lives where

| Content | Repository | Reaches the device as |
|---|---|---|
| Services, the shell, the boot UI, the product host, the SDK | `system` | Development: an extension. Release: `.deb` packages in the OpenDAP repositories (L2), built with cargo-deb (**not built yet**) |
| Tokens, fonts, icons, brand files | `blackbird-ui` `export/` and `brand/svg/` | Compiled in at build time, found through `repos.tsv` |
| Image definition: packages, units, session, boot | `blackbird-os/image/` | The image (L1); its outputs in `image/mkosi.output/` |
| Virtual hardware: layers, models, the virtual board's support package | `virtual-devices` | QEMU's devices; the support package passed into `qemu` images by `odap-image`; the description through fw_cfg |
| Maintainer tools: image, sysroot, cross-build, deploy, development key, security check | `toolkit-image` | Host only |
| Test instrumentation (`odap-inject`) | `toolkit-verify` | A development extension only |

## 6. From development to release

- **Packages.** A change is released as a `.deb` in the OpenDAP repositories (L2), and images are built from those packages (OS-010). Development extensions are only a shortcut to the same files.
- **Checks before a commit:** `cargo test`; `cargo clippy`; for anything with a screen, the virtual device with screenshots; the repository's pre-commit (REUSE).
- **Definition of done** for anything with a screen: exercised on a virtual device, driven through `odap-vdev`, checked functionally and visually from its screenshots, and on the T1 once the hardware exists.

## 7. Conformance with the defined stack

| Decision | In the bring-up |
|---|---|
| ADR 0002 and ADR 0012: own compositor on Smithay, session of a dedicated user | `odap-shell` on Smithay (a pinned revision of master, ADR 0008 O2), started by `odap-shell.service` as `odap` in a logind session through PAM; libseat on logind. No third-party compositor |
| Shell spec §2: DRM/KMS, GBM, GLES, libinput | `DrmCompositor`, `GbmAllocator`, `GlesRenderer`, libinput through the session |
| Shell spec §5: no damage, no frame | A frame only after a client commit or while the splash screen fades; one per refresh; a timer, not frames, waits out the splash screen's minimum |
| Shell spec §9, OS-035: boot | The boot UI (`odap-boot`) shows the splash screen from the first display; the shell takes over without a blank frame; consoles only in the debug boot mode |
| ADR 0006: Slint behind the renderer interface | `odap-product` in Slint with FemtoVG and the software renderer compiled in, selected at run time |
| ADR 0013: hardware described by data | Buttons are roles from the device description, which comes from the hardware (fw_cfg on virtual boards); no board in code |
| ADR 0008: `tracing` to journald | `tracing-journald` when started by systemd, stderr otherwise |
| Design system §18.1: tokens as the single source | Slint globals generated from `opendap.tokens.json`, read from `export/` |

## 8. UI bring-up milestones

| Milestone | Content | State |
|---|---|---|
| **M1** | `odap-shell` shows `odap-product` full screen on a virtual device; touch reaches it; buttons are decoded into roles; the boot UI and splash screen | Verified (§9 and the virtual devices spec) |
| **M2** | The bus (Varlink with `zlink`, ADR 0002): roles reach the product host and the playback service; the shell draws the volume beside the volume controls; the session bus; the shell takes logind's power-key inhibitor | Not started |
| **M3** | Now Playing from the library and audio engine services instead of the fixture; places and gestures between them | Not started |
| **M4** | The measurement gates of shell spec §5.1 on a virtual device (ratios), then on the T1 | Not started |

## 9. Verification (2026-10-23)

Recorded with the names of that day: `dap-*` binaries and scripts, renamed `odap-*` and moved into toolkit-image and virtual-devices later the same day (RFC 0008). The same checks were run again with the new tools.

Host: macOS 27, Apple silicon. Virtual T1 from the `qemu` image built the same day. Evidence: screenshots through `dap-qmp.py screenshot`, the journal over SSH, `/proc` counters.

### Loops

| Case | Steps | Expected | Observed |
|---|---|---|---|
| Sysroot | `dap-sysroot.sh` | The image's packages with headers in a case-sensitive volume | 561 MB; `libinput`, `libseat`, `libudev`, `libgbm`, `libEGL`, `libxkbcommon` and `libwayland-client` present. The first attempt, on the case-insensitive volume, failed on `ipt_ecn.h` / `ipt_ECN.h`; that is why the sparse image exists |
| Cross-build | `scripts/cross.sh build --release -p dap-shell -p dap-product` | aarch64 ELF linked against the image's glibc | Builds in 1 min 41 s from clean. `dap-shell` needs `libgbm.so.1`, `libseat.so.1`, `libudev.so.1`, `libinput.so.10`, `libxkbcommon.so.0`, `libc.so.6`; EGL is loaded at run time |
| Host tests | `cargo test --workspace` | Pass | 5 tests pass; `clippy` clean |
| UI on the host | `cargo run -p dap-product` | Now Playing in a 320 × 480 window | As in the mockup. Battery absent, as it should be on a host without `power_supply` |
| Deploy | `scripts/deploy.sh` | Extension merged, shell restarted, no image rebuild | 2.2 s end to end; `Using extensions 'opendap-dev'`, `Merged extensions into '/usr'` |

### M1 on the virtual T1

| Case | Steps | Expected | Observed |
|---|---|---|---|
| Session | Boot | `dap` in a logind session on seat0, tty1 | Session `c1`, user `dap`, seat0, tty1 |
| Display | Shell start | Panel-sized mode, GLES renderer | Mode 320 × 480 at 60 Hz, chosen from the description. The connector's preferred mode is 1280 × 800, which the first run picked before the fix. Mesa llvmpipe through GBM, because the virtual GPU has no 3D |
| First frame | Screenshot | Now Playing at native size | Matches the mockup; battery 50 % from `test_power` |
| Touch | `dap-inject tap 160 428`, twice | Play, then pause, then play; no stuck pressed state | As expected. Host-side injection (`dap-qmp.py tap`) delivers only `BTN_TOUCH` with no position, slot or tracking id (QEMU 11.1.2), and left the control drawn pressed. `dap-inject` (uinput, in the development extension) is the test path |
| Touch outside a control | `dap-inject tap 160 200` | No change | Screenshot identical |
| Buttons | `dap-qmp.py press action / vol-up / vol-down / power` | Roles from the description | `Action`, `VolumeUp`, `VolumeDown`, `Main`, each pressed and released |
| Main short press | `press power` | Nothing shuts down | Before the fix, logind powered the instance off. Now logind logs "Power key pressed short" and the system stays running |
| Main long press | `press power 6500` | Power off: the fallback when the shell is not running | Powered off while the key was held |
| Battery | `battery_capacity` 7, 50, 100 | Level and glyph follow at the next minute | 7 % shown after the next minute without a restart. The glyph first stayed full at 7 %; it is now drawn with a fill of 1, 5 and 10 px out of 10. One layout regression (the percentage drifting to the centre) was found and fixed in the same pass |
| Product host crash | `kill -9` on `dap-product` | Session restarts by itself | Shell exits, systemd restarts it, the screen returns in about 4–5 s. The screen is black meanwhile (finding) |
| Product host crash, again (after RFC 0008) | `kill -9` on `odap-product` | The display never goes black | The shell stays (same process) and restarts the host. The last frame stays until the new host draws, within 0.5 s. A restart of the shell itself hands the display to `odap-boot`'s splash screen with no blank frame, instead of QEMU's "Display output is not active" |
| Static screen | 20 s, no input, every thread | 0 wakeups (shell spec §5.1) | `dap-shell`: 0. `dap-product`: 40 wakeups from the thread `blocking-1` (a futex timeout twice a second). **Fails the gate.** Probable cause, **UNVERIFIED**: the `blocking` thread pool behind AccessKit's AT-SPI connection, with no session bus in the image (`/run/user/989/bus` is missing) |
| Static screen, again (after RFC 0008) | 50 s within one minute, no input, every thread of `odap-shell` and `odap-product` | 0 wakeups (shell spec §5.1) | 0 in every thread. **Passes.** The cause was not the session bus: `blocking` 1.7.0 (behind zbus, for Slint's accessibility) keeps idle threads alive, waking every 500 ms (smol-rs/blocking#75 changed the exit condition). `odap-product` holds it below 1.7. The session bus (`dbus-user-session`) is in the image anyway, for accessibility over AT-SPI. Once a minute the clock redraws, as it should |

### Not covered, and why

- **The T1:** no hardware yet.
- **Accessibility tree:** AccessKit has no AT-SPI bus to publish to in this image, so what a screen reader is told was not checked. This comes with M2's session bus.
- **Narrow and other displays:** the fixtures exist (`no-display.toml`), but only the virtual T1 runs the shell today.
- **Gestures and places:** M3.
- **Audio:** none of the M1 code produces sound.

### Findings carried to M2

- Product-host wakeups on a static screen. The first step is to add the session bus (`dbus-user-session`) and measure again.
- A black screen while the session restarts after a product-host crash. The shell should keep its frame and restart the client itself once the orchestrator owns activities.
- The logind power-key drop-in is replaced by the shell's `handle-power-key` inhibitor.
