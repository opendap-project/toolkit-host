# Research: software and firmware development toolchain

**Date:** 2026-10-21 · **Status:** research input, not a decision · **Scope:** what OpenDAP needs on developer hosts (macOS Apple Silicon, Linux), in repositories and in CI.

> Everything below is a **recommendation**. Nothing here is confirmed by the maintainers. Choices that depend on the SoC (NXP i.MX 8M Plus, Rockchip RK3576, RK3566) or on the base distro (Debian or Alpine) are marked.
> **UNVERIFIED** means the claim could not be confirmed from a primary source during this research.
> Versions are the latest found on 2026-10-21, mostly from the GitHub releases API or crates.io.

## Context assumed

- All custom software and firmware is written in Rust.
- OpenDAP OS is a trimmed image built from Debian or Alpine packages. It uses mainline kernel 7+ and **no custom kernel builds**.
- Kernel status on 2026-10-21: mainline 7.3 (2026-10-18), stable 7.2.12, latest LTS 6.18.58 ([kernel.org](https://www.kernel.org/)).
- Debian stable is 13 "trixie" (13.7, 2026-09-12) and ships a 6.12 kernel ([debian.org](https://www.debian.org/releases/trixie/)). To get kernel 7+ without building one, the image would have to use trixie-backports, testing ("forky") or Alpine's newer kernel flavours. **UNVERIFIED:** which kernel versions these carry right now. Check this before choosing a distro, because it is the single biggest constraint on the "no custom kernel" rule.
- Helper MCUs:
  - STM32U0 (Cortex-M0+).
  - RP2350 (2× Cortex-M33 plus 2× Hazard3 RISC-V).
- HATs:
  - Oscilloscope (MCU plus FPGA, parts not chosen).
  - VNA based on NanoVNA (STM32F072/F303).
  - SDR based on HackRF (LPC43xx plus CPLD on HackRF One, or iCE40UP5K FPGA on HackRF Pro).

One point simplifies a lot: **Apple Silicon is aarch64**. An arm64 Linux VM or container on a Mac runs the target ISA natively, without emulation. Cross-compiling and building images on macOS therefore mostly means "run an arm64 Linux VM", not "cross-compile from a foreign ISA".

---

## 1. Emulation and simulation

### Need

- Develop the UI and system services (compositor, audio, power, apps) before hardware exists, on both host OSes.
- Smoke-test the real OpenDAP OS image in CI.
- Run MCU firmware without a board where it helps (protocol and state-machine tests).

### Recommended tools

| Tool | Version | License | Maturity | macOS (Apple Silicon) |
|---|---|---|---|---|
| **QEMU** `virt` machine (aarch64) | 11.1.0 (2026-08) ([qemu.org](https://www.qemu.org/blog/2026/08/)) | GPL-2.0 | Very mature | Yes. HVF acceleration runs at near-native speed |
| QEMU `imx8mp-evk` machine | in 11.x ([docs](https://www.qemu.org/docs/master/system/arm/imx8mp-evk.html)) | GPL-2.0 | Young: added in 10.0, KVM patches posted late 2025 | Yes (TCG). For bootloader and kernel bring-up only |
| **UTM** (QEMU front end with ANGLE/virglrenderer) | 5.0.8 (2026-10-17) | Apache-2.0 | Mature | Yes. Best way today to get GL in an arm64 Linux guest on a Mac ([UTM docs](https://docs.getutm.app/updates/v4.1/)) |
| krunkit / libkrun (virtio-gpu Venus on macOS) | krunkit 1.3.2 (2026-07) | Apache-2.0 | Medium. Built for Podman and AI workloads, not for desktops | Yes, macOS 14+ only ([repo](https://github.com/libkrun/krunkit)) |
| **Renode** | 1.17.0 (2026-09-07) ([releases](https://github.com/renode/renode/releases)) | MIT | Mature for MCUs | Yes. Native arm64 macOS since 1.17 |

**QEMU `virt` with virtio for OpenDAP OS UI work.** This is the main recommendation. A "QEMU flavour" of the OpenDAP OS image boots the same rootfs with a generic arm64 kernel and DTB-less ACPI or `virt` DT. It uses:

- `virtio-gpu` (2D) or `virtio-gpu-gl` (virgl). Guest Wayland compositors run on virtio-gpu through Mesa's `virgl` driver, or on `llvmpipe` with 2D only.
- **virtio-snd** (`-device virtio-sound-pci,audiodev=…`) with backends PulseAudio, ALSA, SDL and **CoreAudio**. The guest needs `CONFIG_SND_VIRTIO` ([QEMU docs](https://www.qemu.org/docs/master/system/devices/virtio/virtio-snd.html)). Today the device has playback-first streams and no jack or chmap configuration, which is enough for PipeWire and ALSA development, not for testing capture paths.
- virtio-input (keyboard, tablet), virtio-net, virtio-blk and virtio-rng.

On a **Linux host**, `virtio-gpu-gl` with virglrenderer gives GL 4.3 (4.6 with blob resources). Venus gives Vulkan. Rutabaga/gfxstream adds **Wayland passthrough** through the cross-domain context ([virtio-gpu docs](https://www.qemu.org/docs/master/system/devices/virtio/virtio-gpu.html)).

On **macOS**, upstream Homebrew QEMU is built without OpenGL, so `-display cocoa,gl=es` fails ([QEMU issue 2443](https://gitlab.com/qemu-project/qemu/-/issues/2443)). Venus for macOS was still an RFC in Dec 2025 ([patchew](https://patchew.org/QEMU/20251203040754.94487-1-j@getutm.app)). On a Mac, use UTM's patched QEMU (virgl over ANGLE/Metal) or accept 2D virtio-gpu with llvmpipe in the guest. **UNVERIFIED:** whether UTM's GL path works for a headless or scripted (CLI) workflow. UTM ships `utmctl`.

#### Renode for MCUs

- Good STM32 coverage. 1.17 added work on STM32 F0/F1/F4/F7/L5/WBA and Cortex-M52.
- **No STM32U0 or RP2350 platform was found** in the 1.17 notes. **UNVERIFIED:** community RP2040 models exist and RP2350 status is unknown.
- Renode gained an **i.MX 8M Plus** platform in 2026 ([Antmicro blog](https://antmicro.com/blog/2026/06/renode-support-for-nxp-imx8m-plus)). It covers A53, GIC, uSDHC, UART, GPIO, GPT and FlexCAN, and it boots TF-A, U-Boot and Linux "with limitations". There is no display or audio.

### Gaps and fallbacks

- **No emulator models the candidate board.** The `imx8mp-evk` machine in QEMU has no display, GPU, audio or ISP. Use it only for U-Boot and kernel boot checks, never for UI work.
- MCU emulation for STM32U0 and RP2350 is weak. Fall back to:
  - **host-side unit tests**: put logic in `no_std` crates that also build for the host and test with `cargo test`. This is the main strategy;
  - `embedded-hal-mock` or trait mocks;
  - HIL (section 7).
- Hardware-in-the-loop alternative for the SoC before the OpenDAP board exists: use a **vendor EVK or SBC for the chosen SoC** as the reference target. For i.MX 8M Plus that means the NXP EVK, FRDM-IMX8MPLUS, Toradex Verdin or PHYTEC boards. For RK3576 it means Radxa ROCK 4D, NanoPi M5 or ArmSoM Sige5. For RK3566 it means Radxa ROCK 3C, Pine64 Quartz64 or Radxa Zero 3. These boards are what labgrid would drive at first.

### SoC-specific notes

- **i.MX 8M Plus:** the only candidate with upstream models in QEMU and Renode. That helps bootloader and CI work, not UI work.
- **RK3576 and RK3566:** no Rockchip machine model exists in upstream QEMU. The full list of Arm boards in QEMU master has none ([target-arm](https://www.qemu.org/docs/master/system/target-arm.html)). There is none in Renode either. Use `virt` for software work and SBCs for real-hardware work.

---

## 2. Rust cross-compilation

### Need

Reproducible builds of:

- Linux userspace Rust binaries for aarch64 that link against distro libraries (ALSA, PipeWire, Wayland, libinput, Mesa/EGL/GBM, systemd or elogind, D-Bus);
- `no_std` firmware for the MCUs.

All of it from macOS and Linux hosts and CI, with pinned toolchains.

### Targets

| Component | Rust target | Notes |
|---|---|---|
| OpenDAP OS userspace, Debian | `aarch64-unknown-linux-gnu` (Tier 1) | Must match the distro glibc (trixie: glibc 2.41, **UNVERIFIED**) |
| OpenDAP OS userspace, Alpine | `aarch64-unknown-linux-musl` (Tier 2 with host tools) | Dynamic linking against Alpine's musl libs is needed for Mesa and PipeWire. Rust defaults to static musl, so set `-C target-feature=-crt-static` |
| Standalone static tools (installers, recovery, CI helpers) | `aarch64-unknown-linux-musl` static | Runs on either distro |
| STM32U0 (Cortex-M0+) | `thumbv6m-none-eabi` | No hardware atomics. Use `portable-atomic` or `critical-section` |
| RP2350 Arm cores (M33, FPU) | `thumbv8m.main-none-eabihf` | Main target ([Raspberry Pi: Rust on RP2350](https://www.raspberrypi.com/news/rust-on-rp2350/)) |
| RP2350 RISC-V cores (Hazard3) | `riscv32imac-unknown-none-elf` | Supported by Embassy and rp235x-hal. Less tested |
| NanoVNA MCU (if ever rewritten) | `thumbv6m-none-eabi` (F072), `thumbv7em-none-eabihf` (F303) | Upstream firmware is C |
| HackRF MCU LPC43xx (M4F) | `thumbv7em-none-eabihf` | Upstream firmware is C |

The choice between **glibc and musl follows the distro choice**. It is not a separate decision. Debian means `-gnu`; Alpine means `-musl` with dynamic linking.

### Recommended tools

| Tool | Version | License | macOS | Use |
|---|---|---|---|---|
| rustup + `rust-toolchain.toml` | Rust **1.99.1** (2026-10-15) ([blog](https://blog.rust-lang.org/releases)) | MIT/Apache-2.0 | Yes | Pin channel, components and targets per repo |
| **Native arm64 Linux container or VM** (Debian or Alpine base matching OpenDAP OS) | n/a | n/a | Yes, native speed on Apple Silicon | **Main path for anything linking system libs**: `apt install libasound2-dev libpipewire-0.3-dev libwayland-dev …` or the `apk` equivalents, then plain `cargo build` |
| **cargo-zigbuild** | 0.24.0 (2026-10-21) | MIT | Yes (arm64 binaries) | Cross-linking with a chosen glibc version (`--target aarch64-unknown-linux-gnu.2.36`) without a cross GCC. Good for pure-Rust crates and for linking against a sysroot |
| Zig (linker for zigbuild) | 0.15.2 | MIT | Yes | Pin it, because zigbuild behaviour follows Zig versions |
| cross (cross-rs) | 0.2.5. The last release is old (2023-02, per the GitHub API) | MIT/Apache-2.0 | Partial. Its images are x86_64 and run under emulation on Apple Silicon | **Not recommended** as the main tool. Its sysroots are Ubuntu-based and do not match OpenDAP OS |
| Debian multiarch sysroot (`mmdebstrap --variant=extract --architectures=arm64 … libasound2-dev …`) | mmdebstrap 1.5.7 | MIT | Linux, or a Linux VM on Mac | Sysroot that matches the target exactly, for zigbuild or clang cross-linking from x86_64 CI |
| `pkg-config` with `PKG_CONFIG_SYSROOT_DIR` and `PKG_CONFIG_PATH` | n/a | n/a | Yes | Needed by `alsa-sys`, `pipewire-sys`, `wayland-sys` and similar crates |
| cargo-deb (Debian) / `abuild` (Alpine) | **UNVERIFIED** current versions | MIT / GPL | Yes / container | Package Rust binaries as distro packages so the image builder installs them like any other package |
| cargo-binstall | 1.26.0 | GPL-3.0 | Yes | Fast, pinnable install of cargo tools in CI |
| cargo-nextest, cargo-deny | 0.9.149, 0.20.2 | Apache/MIT | Yes | Tests and license or advisory gating (open-source-first policy) |

Practical rules:

- Put `rust-toolchain.toml` in every repo with `channel = "1.99.1"` (an exact version, not `stable`), `components = ["rustfmt","clippy","llvm-tools","rust-src"]`, and `targets` listing every target the repo builds.
- Commit `Cargo.lock`, including in libraries that ship firmware.
- Set `SOURCE_DATE_EPOCH`, and add `--remap-path-prefix` (or `trim-paths` once it is stable; **UNVERIFIED** status in 1.99) for reproducible binaries.
- From x86_64 CI, the cleanest route is to build natively on **arm64 runners** (section 7) inside the OpenDAP OS base container. That removes most cross-linking problems.

### Gaps and fallbacks

- Linking Mesa, PipeWire or Wayland through zigbuild against a sysroot works, but setting it up is fiddly (rpath and `.so` symlinks in the sysroot). The native arm64 container is the robust default. Keep zigbuild for pure-Rust daemons and tools.
- musl userspace with Mesa or GPU drivers works on Alpine. Allocator performance on musl is a known weakness; consider `mimalloc` for heavy services.

### SoC-specific notes

- All three SoCs are Cortex-A53/A55/A72-class arm64. The Rust target is the same. Only `-C target-cpu` tuning differs:
  - i.MX 8M Plus: A53;
  - RK3566: A55;
  - RK3576: A72 plus A53. **UNVERIFIED** core mix wording: some sources say A72+A53.
- Keep the default generic `aarch64` for portability across SoCs. Tune only after the SoC is chosen.

---

## 3. Embedded Rust stack for MCUs, plus FPGA toolchains for HATs

### Need

- Firmware for STM32U0 and RP2350 helper MCUs, and possibly for HAT MCUs.
- Flash, debug and log over SWD.
- Build or vendor the HackRF and NanoVNA firmware.
- Build FPGA bitstreams for the scope and SDR HATs with open tools.

### Recommended tools

| Tool | Version | License | Maturity | macOS |
|---|---|---|---|---|
| **Embassy** (`embassy-executor` 0.10.0, `embassy-stm32` 0.6.0, `embassy-rp` 0.10.0, `embassy-time` 0.5.1) | crates.io 2026-03-20 | MIT/Apache-2.0 | Production-used, pre-1.0 | Yes |
| `embassy-stm32` **STM32U0** | Feature flags exist (`stm32u031c6`, `stm32u073c8`, `stm32u083cc` and others) ([docs.rs](https://docs.rs/crate/embassy-stm32/latest/features)) | same | **UNVERIFIED** per-peripheral completeness for U0 (LCD, LPUART, USB). Validate on a Nucleo-U083RC early | Yes |
| `embassy-rp` **RP235x** | RP2040 and RP23xx supported ([README](https://github.com/embassy-rs/embassy)) | same | Good, including PIO | Yes |
| rp235x-hal (rp-hal, non-async alternative) | 0.4.0 (2026-02) | MIT/Apache-2.0 | "Volatile until 1.0" | Yes |
| **probe-rs** (`probe-rs run`, `cargo-embed`, DAP server for VS Code and Zed, GDB stub) | 0.32.0 (2026-07-22) ([releases](https://github.com/probe-rs/probe-rs/releases)) | MIT/Apache-2.0 | Mature | Yes (arm64 binaries) |
| **defmt** / defmt-rtt | 1.2.0 / 1.3.1 (2026-10-15) | MIT/Apache-2.0 | Stable 1.x ([Ferrous](https://ferrous-systems.com/blog/defmt-1-0/)) | Yes |
| flip-link (stack-overflow protection) | 0.1.12 | MIT/Apache-2.0 | Stable | Yes |
| picotool (RP2350 UF2, OTP, partition tables, secure boot signing) | 2.3.1 (2026-09-05) | BSD-3 | Official | Yes (Homebrew, **UNVERIFIED** formula version) |
| elf2uf2-rs | 2.2.0 | 0BSD | OK for RP2040. **Prefer picotool for RP2350** | Yes |
| Debug probe | Raspberry Pi Debug Probe (CMSIS-DAP), ST-LINK V3, J-Link | open fw / proprietary | n/a | n/a |
| **OpenOCD** (fallback) | 0.12.0 is still the last tagged release (2023-01). Distros and RPi ship git snapshots | GPL-2.0 | Mature | Yes (Homebrew) |
| Arm GNU Toolchain (for the C HAT firmwares, plus `arm-none-eabi-gdb`) | 15.2.Rel1 ([Arm](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads)) | GPL | Mature | Yes, darwin-arm64 |

Notes on the tools:

- **RP2350 in probe-rs:** needs ADIv6, which landed in 0.27. 0.32 adds initial support for the RISC-V cores.
- **STM32U0 in probe-rs:** target YAML files are generated from CMSIS packs. **UNVERIFIED:** whether an `STM32U0_Series.yaml` ships. Check with `probe-rs chip list | grep U0`. The fallback is to generate one with `target-gen` from ST's DFP.
- **probe-rs DAP server:** since 0.32 it can talk over stdio. RTT plus defmt is the logging path.
- **Rust RP2350 secure boot:** picotool signs images; probe-rs flashes them.
- **OpenOCD:** use it when probe-rs lacks a target, for SoC JTAG (section 5) and for SVF/XSVF CPLD programming.

#### FPGA toolchain (HATs)

| Tool | Version | License | macOS |
|---|---|---|---|
| **OSS CAD Suite** (bundles Yosys, nextpnr-ice40/ecp5/gowin/nexus, icestorm, Trellis, Apicula, openFPGALoader, iverilog, Verilator, GTKWave, Amaranth, SBY) | Nightly, `2026-10-21` build ([repo](https://github.com/YosysHQ/oss-cad-suite-build)) | ISC (bundle) plus component licenses | **Yes, darwin-arm64** |
| Yosys / nextpnr | 0.70 (2026-10-13) / 0.11.1 (2026-08-11) | ISC | Yes |
| Amaranth HDL (needed for HackRF Pro gateware) | **UNVERIFIED** current version | BSD-2 | Yes |

Pin one dated OSS CAD Suite build per repo and record its date in the repo, because there are no semver releases. Lattice iCE40 and ECP5 and Gowin parts give a fully open flow. **Recommendation for the oscilloscope HAT FPGA: choose a part with a mature open flow** (iCE40UP5K, ECP5, or Gowin GW1N/GW2A through Apicula). Xilinx and Intel parts would force proprietary tools into CI.

#### How the reference HAT firmwares are built today

- **HackRF** (latest firmware v2026.01.3, 2026-01-30, with HackRF Pro support since 2026.01.1):
  - MCU firmware is C on LPC43xx, built with CMake and `arm-none-eabi-gcc`. **UNVERIFIED** exact dependency list; check `firmware/README`.
  - Flashed with `hackrf_spiflash`, or by DFU recovery with `dfu-util` ([docs](https://hackrf.readthedocs.io/en/latest/updating_firmware.html)).
  - HackRF One CPLD bitstreams are prebuilt XSVF files. **UNVERIFIED:** whether they are still built with Xilinx ISE, which is proprietary.
  - **HackRF Pro** uses a **Lattice iCE40UP5K**. Its gateware is written in **Amaranth** and built with the open iCE40 toolchain, then bundled into the firmware ([gateware docs](https://hackrf.readthedocs.io/en/latest/gateware.html)). That is a good fit for OSS CAD Suite.
- **NanoVNA-H / H4 / -D** (DiSlord):
  - C firmware on ChibiOS, built with `make` and `arm-none-eabi-gcc` (upstream recommends GCC 8; newer versions "may cause exceptions"). `TARGET=F072` or `F303`.
  - Flashed with `dfu-util` ([NanoVNA-D](https://github.com/Ho-Ro/NanoVNA-D), [hugen79/NanoVNA-H](https://github.com/hugen79/NanoVNA-H/releases)).
  - Keep the legacy GCC pinned in a container, not on hosts.

### Gaps and fallbacks

- The STM32U0 HAL depth in Embassy is unproven. The fallback is the `stm32-metapac` PAC plus hand-written drivers, or the RP2350 for that role.
- RP2350 RISC-V Rust is less mature. Default to the M33 cores.
- The HackRF and NanoVNA firmwares are GPL C. Treat them as vendored upstream builds in containers. Do not rewrite them in Rust unless there is a product reason.

---

## 4. Flashing and provisioning the SoC

### Need

- Recover a bricked board over USB.
- Provision eMMC in the factory.
- Flash SD and eMMC images quickly during development.
- Build the boot chain from mainline sources, with blobs vendored and pinned.
- Optionally use secure boot.

### Common tools

| Tool | Version | License | macOS |
|---|---|---|---|
| **bmaptool** | 3.9.0 ([repo](https://github.com/yoctoproject/bmaptool/releases)) | GPL-2.0 | Works with Python. Raw-disk access on macOS is **UNVERIFIED**; `dd` to `/dev/rdiskN` is the fallback |
| U-Boot (mainline) | 2026.10 expected (**UNVERIFIED**; U-Boot ships quarterly) | GPL-2.0 | Builds in a Linux container |
| TF-A (upstream) | **UNVERIFIED** latest (2.13/2.14) | BSD-3 | Container |
| U-Boot `ums` (USB mass storage gadget) and `fastboot` | in U-Boot | GPL-2.0 | Host side: works with any OS. Fastboot comes from Android platform-tools (Apache-2.0) |
| dfu-util | **UNVERIFIED** latest (0.11) | GPL-2.0 | Yes |

Development loop (all SoCs):

1. Build the `.img` plus `.bmap`.
2. `bmaptool copy` to SD, or to eMMC exposed by U-Boot `ums 0 mmc 0` over USB-C.

Use the USB gadget recovery path as the "no SD card" path.

### i.MX 8M Plus

- **uuu (mfgtools)** 1.5.243 (2025-12-16), BSD-3. Install with `brew install uuu` (macOS arm64) or Debian `mfgtools` ([formula](https://formulae.brew.sh/formula/uuu), [repo](https://github.com/nxp-imx/mfgtools)). It drives the ROM's Serial Download Protocol (SDP), the SPL, and U-Boot fastboot. One `.uuu` script does a full eMMC provisioning.
- **Boot chain fully from mainline:**
  - U-Boot `imx8mp_evk` style defconfig, with binman producing `flash.bin`;
  - upstream TF-A `PLAT=imx8mp`. The U-Boot EVK doc still points at NXP's imx-atf fork; board docs (Toradex, PHYTEC) use upstream ([Toradex doc](https://docs.u-boot.org/en/latest/board/toradex/smarc-imx8mp.html), [EVK doc](https://docs.u-boot.org/en/latest/board/nxp/imx8mp_evk.html));
  - **DDR PHY training firmware** from NXP `firmware-imx`. This is a binary blob, redistributable under the NXP EULA. Vendor it and pin it by hash.
- **Secure boot:** HABv4. Mainline U-Boot wraps the SPL and FIT in the `nxp-imx8mcst` binman etype when `CONFIG_IMX_HAB=y`. Signing uses NXP's **CST** (free download; **UNVERIFIED** license and whether the source is open). References: [Foundries HABv4 guide](https://docs.foundries.io/95/reference-manual/security/secure-boot-imx-habv4.html), AN4581.

### RK3566 / RK3576

- **Recovery and flash tools:**
  - `rkdeveloptool`: C, GPL-2.0, Debian package `1.32+pine64git20240226`; builds on macOS from source ([Radxa macOS guide](https://docs.radxa.com/en/rock5/rock5a/low-level-dev/maskrom/mac-os));
  - **`rockusb`**: Rust, MIT/Apache-2.0, 0.4.0, 2026-09, from Collabora ([rockchiprs](https://github.com/collabora/rockchiprs)). Install with `cargo install rockusb --example rockusb --features=nusb`. It is pure Rust and uses nusb, so it is cross-platform. **Recommended** for the Rust-first policy, with rkdeveloptool as the fallback.
  - Maskrom needs a loader built from rkbin (`boot_merger`), or the U-Boot SPL with USB download. **UNVERIFIED** for RK3576.
- **RK3566 boot chain:** mainline U-Boot and **upstream TF-A BL31** are both supported. The DDR init **TPL blob comes from rkbin** ([U-Boot Rockchip doc](https://docs.u-boot.org/en/latest/board/rockchip/rockchip.html)).
- **RK3576 boot chain:**
  - mainline U-Boot supports several boards (ROCK 4D, NanoPi M5, Sige5 and others), and UFS boot patches were in review in May 2026 ([u-boot list](https://lists.denx.de/pipermail/u-boot/2026-May/618327.html));
  - the U-Boot doc lists **BL31 and DDR both from rkbin** for RK3576. One survey says upstream TF-A has basic RK3576 support ([Flipper RK3576 mainlining](https://docs.flipper.net/one/cpu-software/rk3576-mainlining)); **UNVERIFIED** whether it is upstream;
  - **no OP-TEE**.
  - So RK3576 has **more blobs** than RK3566 or the i.MX 8M Plus.
- **Secure boot:** the ROM checks the hash of a public key burned into OTP, then the signed TPL and SPL; SPL then verifies the FIT. There are public guides for RK3568 with mainline U-Boot ([3mdeb](https://blog.3mdeb.com/2025/2025-04-22-odroid-m1-secure-boot/)) and RK3588 with barebox ([Pengutronix 2026-06](https://www.pengutronix.de/en/blog/2026-06-19-rk3588-secure-boot.html)). The signing tools are partly Rockchip's (`rk_sign_tool`, proprietary). **UNVERIFIED** for RK3576.

### Gaps and fallbacks

- Every SoC needs at least one DDR blob. Keep a `boot-firmware` repo that stores the blobs pinned by SHA-256 and records their licenses.
- macOS USB access for uuu, rockusb and DFU works through libusb or nusb. For factory provisioning, a Linux host or a small "flash station" SBC is the safer recommendation.

---

## 5. Debugging

### Need

- Debug Rust services on the target.
- Debug early boot and kernel hangs.
- Profile UI and audio latency.
- Collect crashes from field units.

### Recommended tools

| Area | Tool (version) | License | macOS host |
|---|---|---|---|
| Remote userspace debug | `gdbserver` on target (Debian `gdbserver`, Alpine `gdb` package) plus host `gdb` with multiarch support; or `lldb-server platform` on target plus host `lldb` / `rust-lldb` | GPL / Apache-2.0 (LLVM) | **LLDB is the easier path on macOS.** It comes with Xcode CLT or Homebrew `llvm` and debugs aarch64-linux remotely. Homebrew `gdb` runs on Apple Silicon ([formula](https://formulae.brew.sh/formula/gdb)); **UNVERIFIED** whether it was built with `--enable-targets=all` for aarch64-linux remote use. The fallback is gdb inside the Linux VM |
| Transport | gdbserver over TCP on USB-C **CDC-NCM/ECM gadget** Ethernet (the same cable as power and ADB-like access) or Wi-Fi; serial console through a USB-UART | n/a | Yes |
| IDE | VS Code or Zed with CodeLLDB (Linux remote); probe-rs DAP (MCU) | MIT | Yes |
| Serial console | `tio` (**UNVERIFIED** version), `picocom`; target `agetty` on UART2/debug UART; U-Boot console | GPL | Yes (Homebrew) |
| SoC JTAG | OpenOCD 0.12 or git with a CMSIS-DAP or J-Link probe. i.MX 8M Plus: `target/imx8mp.cfg` (**UNVERIFIED**; an `imx8m` config exists). Rockchip: JTAG is muxed on SD pins and often disabled by default, so **UNVERIFIED** for RK3576 | GPL-2.0 | Yes |
| Kernel tracing | `perf`, ftrace with `trace-cmd` and KernelShark, eBPF with `bpftrace` (all from distro packages, matched to the distro kernel, so no custom kernel is needed) | GPL | Analysis on host |
| Rust profiling | **samply** 0.13.1 (record on target, Firefox Profiler UI on host; `samply import perf.data`) ([repo](https://github.com/mstange/samply)) | MIT/Apache-2.0 | Yes |
| Frame and latency profiling | **Tracy** 0.14.1 (2026-08-22) with the `tracy-client` crate 0.19.0. The GUI runs on macOS and Linux; the target streams over the network | BSD-3 | Yes |
| Crash collection | `systemd-coredump` plus `coredumpctl` (Debian). Alpine has no systemd, so use `kernel.core_pattern` to a handler. **Rust in-process:** `crash-handler` 0.8.1 plus `minidumper` 0.11.0 (minidumps, symbolicated offline with `minidump-stackwalk`); `panic = "abort"` hooks | MIT/Apache | Yes |
| MCU | probe-rs plus defmt and RTT; `arm-none-eabi-gdb` through the probe-rs GDB stub | | Yes |

Since Rust 1.89, non-leaf **frame pointers are on by default for `aarch64-unknown-linux-gnu`**, which makes perf and samply stacks work out of the box ([source](https://oneuptime.com/blog/post/2026-01-07-rust-profiling-perf-flamegraph/view); **UNVERIFIED** against the Rust release notes, and also check the `-musl` target).

### Gaps and fallbacks

- No GPU profiler is listed yet. That depends on the SoC:
  - i.MX 8M Plus (Vivante GC7000UL): open driver `etnaviv` in Mesa;
  - RK3566 (Mali-G52) and RK3576 (Mali-G52 MC3, **UNVERIFIED**): `panfrost` / `panthor`.
  - Mesa's own `perfetto` integration is the open route. **UNVERIFIED** for etnaviv.
- Crash upload from field units needs a small backend. That is out of scope here.

---

## 6. Image building (Debian or Alpine, no Buildroot)

### Need

A declarative, reproducible, CI-buildable arm64 image:

- partitions (A/B or rootfs plus data);
- the boot firmware from section 4;
- distro kernel, rootfs, overlays and in-house `.deb` or `.apk` packages;
- output as `.img` + `.bmap`, plus a QEMU flavour.

### Tools

| Tool | Version | License | Distro | arm64 cross build | macOS | Reproducibility |
|---|---|---|---|---|---|---|
| **mmdebstrap** | 1.5.7 (trixie: 1.5.7-1+deb13u1) | MIT | Debian | Foreign arch through **qemu-user plus binfmt**. On an arm64 host it is native. Hooks customise everything | Inside a Linux VM or container | **Bit-for-bit with `SOURCE_DATE_EPOCH`** plus a snapshot.debian.org mirror ([packages](https://packages-pkgmirror-csail.debian.org/tr/sid/mmdebstrap)) |
| **debos** | 1.1.7 (2026-02-06) ([releases](https://github.com/go-debos/debos/releases)) | Apache-2.0 | Debian (YAML recipes; partitioning, raw writes, `install-deb`) | Uses **fakemachine** (a KVM, UML or QEMU VM) plus qemu-user-binfmt. Arm64 Docker image exists | Docker image on Linux. On macOS it needs a Linux VM with KVM, because nested virtualisation on Apple Silicon is limited. **UNVERIFIED** in Apple container or Lima | Good. Recipes are declarative; depends on mirror snapshots |
| **mkosi** | **v27.1** (2026-09) ([releases](https://github.com/systemd/mkosi/releases)) | LGPL-2.1 | Debian yes, **Alpine no** | Foreign architecture through `Architecture=` plus binfmt (**UNVERIFIED** for details in v27). Strong at systemd-boot, UKI, verity and A/B (`systemd-repart`, `systemd-sysupdate`) | Linux only, so use a VM | Good. Pins with `SourceDateEpoch=` and mirror snapshots |
| vmdb2 | **UNVERIFIED** version (0.4x) | GPL-3.0 | Debian | qemu-user binfmt | Linux VM | Moderate. Fewer features than debos |
| **alpine-make-rootfs** | 0.8.1 (Alpine 3.24 package) ([pkgs](https://pkgs.alpinelinux.org/package/v3.24/main/x86_64/alpine-make-rootfs)) | MIT | Alpine | Foreign arch through qemu-user binfmt. Native on arm64 | Linux VM or container | Moderate. Pin the apk repo plus a package list, and note that apk has no snapshot mirror |
| Alpine `aports/scripts/mkimage.sh` | follows aports | MIT/GPL mix | Alpine | Native or binfmt | Linux | Designed for ISO and netboot. Less suited to a custom handheld image |
| apko (Chainguard) | **UNVERIFIED** version | Apache-2.0 | Alpine-compatible apk repos | **No emulation needed**: it only unpacks packages. Post-install scripts are not run | Yes | **Strong** (lockfiles, reproducible). Designed for OCI images; a disk image needs extra steps |
| genimage / systemd-repart | **UNVERIFIED** / systemd 25x | GPL / LGPL | Any | Host-side partition assembly, no emulation | Linux | Deterministic |

How each handles arm64 on the hosts:

- **Linux x86_64:** `binfmt_misc` with `qemu-user-static` or `qemu-user-binfmt` and the `F` flag runs maintainer scripts at TCG speed. It works but is slow, so prefer arm64 CI runners.
- **Linux arm64 or macOS Apple Silicon:** run the builder in an **arm64 Linux VM or container**. That is native, with no binfmt.
  - VM and container options: OrbStack (proprietary), Docker Desktop (proprietary), **Lima 2.2.1** (Apache-2.0), or **Apple `container` 1.0** (Apache-2.0, June 2026, macOS 26 recommended) ([Apple container](https://www.opensourceforu.com/2026/06/apple-launches-container-to-run-linux-containers-inside-micro-vms-on-mac/)).
  - Loop devices and privileged mounts need a full VM (Lima). Plain containers are not enough. **UNVERIFIED** for Apple `container`.

### Recommendation

- **If Debian:** mmdebstrap for the rootfs (reproducible) plus systemd-repart or genimage for the disk, driven by a small Rust or `just` task runner. Or use **debos** if YAML recipes are preferred, at the cost of needing KVM. mkosi is attractive if OpenDAP OS adopts systemd A/B updates (`systemd-sysupdate`, verity, UKI). Prototype both against the update strategy.
- **If Alpine:** alpine-make-rootfs plus genimage. Evaluate apko for a reproducible rootfs layer.
- In both cases, use the **distro kernel package** (no custom builds) and a pinned package snapshot. Keep the boot firmware from section 4 as a separate, pinned artifact that the image builder pulls in.

---

## 7. Testing on real hardware and CI

### Need

- Automated boot, flash and test cycles on real boards (EVK or SBC now, OpenDAP boards later).
- CI that builds firmware, packages and images for every repo.
- Cache Rust builds.

### Tools

| Tool | Version | License | Notes |
|---|---|---|---|
| **labgrid** | 26.0.1 (2026-10-14) ([changes](https://labgrid.readthedocs.io/en/latest/changes.html)) | LGPL-2.1 | Python and pytest. Has drivers **`UUUDriver`, `IMXUSBDriver`, `RKUSBDriver`, `DFUDriver`, `OpenOCDDriver`, `QEMUDriver`, `USBSDMuxDriver`, `USBSDWireDriver`** (from the [configuration docs](https://labgrid.readthedocs.io/en/latest/configuration.html)), plus power switches (Shelly, tcPDU, Modbus relays). Best fit for a small lab. The exporter runs on Linux; the client works on macOS (**UNVERIFIED**) |
| LAVA | 2026.07 ([announce](https://op-lists.linaro.org/archives/list/lava-users@lists.lavasoftware.org/2026/8/)) | GPL-2.0 | Heavier server and dispatcher setup, used by KernelCI. Consider it only if OpenDAP contributes to KernelCI or needs a multi-site farm |
| SD mux hardware | USB-SD-Mux (Linux ioctls) ([usbsdmux](https://github.com/pengutronix/usbsdmux)); SDWire | open hardware | Lets CI write SD images without touching the board |
| GitHub Actions arm64 Linux runners (`ubuntu-24.04-arm`) | GA for **public repos, free** since 2025-08 ([changelog](https://github.blog/changelog/2025-08-07-arm64-hosted-runners-for-public-repositories-are-now-generally-available/)) | n/a | Native aarch64 builds of packages and images (4 vCPU Cobalt 100). Private repos need paid larger runners (**UNVERIFIED** current terms). **KVM on these runners is UNVERIFIED**, and it matters for debos and fast QEMU |
| Self-hosted runner (lab host) | n/a | n/a | Required for HIL jobs (USB to boards). Use labels such as `hil-imx8mp` |
| **sccache** | 0.18.0 (2026-09-14) | Apache-2.0 | GHA cache, S3 or R2 backends. Rust compile caching across repos |
| `Swatinem/rust-cache` action | **UNVERIFIED** version | MIT | Simpler per-repo target-directory caching. Combine it with sccache or use it on its own |
| cargo-nextest | 0.9.149 | Apache/MIT | JUnit output for CI |

Recommended CI layering:

1. Host unit tests and lint on any runner.
2. Firmware builds for the `thumbv*` and RISC-V targets on any runner.
3. arm64 packages and the image on `ubuntu-24.04-arm`.
4. QEMU `virt` boot smoke test of the image: does it boot to the compositor, does audio enumerate, done by screenshot through QMP plus a serial log.
5. labgrid HIL on a self-hosted lab runner, nightly or on demand.

---

## 8. Packaging the dev environment

### Need

One reproducible toolchain definition shared by many repos (OS, apps, firmware for each MCU, HAT gateware, boot firmware, docs), working on macOS and Linux and identical in CI.

### Options

| Option | Version | License | macOS | Fit |
|---|---|---|---|---|
| **Host-native: rustup plus `rust-toolchain.toml` plus mise** | mise v2026.10.17 | MIT | Yes | Light. mise pins cargo tools, zig, probe-rs, just and others per repo through `mise.toml` and a lockfile. Rust targets and components can be scoped per task ([release notes](https://newreleases.io/project/github/jdx/mise/release/v2026.4.13)) |
| **Dev container / OCI image** (Debian or Alpine base **identical to OpenDAP OS**, arm64 and amd64) | devcontainer spec, **UNVERIFIED** CLI version | MIT | Yes, through Docker, OrbStack or Lima. Apple `container` support for devcontainers is **UNVERIFIED** | The **same image is the CI build image and the sysroot**. Best for anything that links distro libs or builds images |
| Nix flakes plus devenv | devenv 2.4.0; Determinate Nix installer | LGPL / Apache | Yes (good on Apple Silicon) | Most reproducible. Cross toolchains for aarch64-linux from a Mac are possible but heavy. Steeper learning curve; nixpkgs does not match the Debian or Alpine sysroot |

### Recommendation

Use a **hybrid**:

1. **On the host**, install only what touches USB hardware or is interactive. That means probe-rs, uuu, rockusb or rkdeveloptool, dfu-util, picotool, openFPGALoader, bmaptool, a serial terminal, QEMU or UTM, and the Tracy and samply viewers. Add rustup with the embedded targets, because MCU work is pleasant natively. Pin all of these with **mise**, using a shared `mise.toml` template.
2. **In a container**, keep anything that links OpenDAP OS libs, builds packages or images, or needs a legacy GCC (NanoVNA). Publish versioned images `ghcr.io/opendap/build-{debian,alpine}:<date>` and `ghcr.io/opendap/fw-legacy-gcc:<ver>`, built from a dedicated `toolchain` repo.
3. **Share** through a `toolchain` repo containing:
   - the container definitions;
   - a canonical `rust-toolchain.toml`;
   - a `mise.toml` template;
   - a reusable GitHub Actions workflow (`workflow_call`);
   - the pinned OSS CAD Suite date.

   Repos reference it by tag. Renovate can bump the pins.
4. Keep Nix as an option to evaluate later. Do not make it the default unless contributors ask for it.

---

## Prioritised list (recommendations, not decisions)

### Needed now (before the SoC is chosen)

1. Create the `toolchain` repo: pinned `rust-toolchain.toml` (1.99.1), `mise.toml`, build containers for **both** Debian trixie and Alpine 3.24 (arm64 and amd64), and a reusable CI workflow with sccache.
2. CI on `ubuntu-24.04-arm` (public repos) with cargo-nextest and cargo-deny (license policy).
3. QEMU `virt` dev image with virtio-gpu, virtio-snd and virtio-input for UI and audio work. On Linux hosts use virgl; on Macs use UTM or 2D llvmpipe. Prototype both distros through the same pipeline to inform the distro choice.
4. **Resolve the kernel 7+ without custom builds question for each distro.** It is a hard constraint.
5. MCU firmware skeletons on Embassy for RP2350 (`thumbv8m.main-none-eabihf`) and STM32U0 (`thumbv6m-none-eabi`) with probe-rs, defmt and flip-link, on dev boards (Pico 2, Nucleo-U0). Verify the U0 HAL depth and the probe-rs target.
6. OSS CAD Suite pinned by date. Choose an oscilloscope FPGA with an open flow.

### Once the SoC is chosen

1. Buy two or three EVKs or SBCs of that SoC as reference targets.
2. Create the boot-firmware repo: mainline U-Boot, upstream TF-A where available, and vendored DDR and other blobs with hashes and licenses.
3. Pick the recovery tooling: uuu (i.MX) or rockusb with an rkdeveloptool fallback (Rockchip). Add it to the host install.
4. Image builder decision: mmdebstrap or debos or mkosi (Debian), or alpine-make-rootfs with apko (Alpine). Output `.img` + `.bmap`.
5. A labgrid lab with one board, a USB-SD-Mux or SDWire, a switched PDU and a USB-UART.

### At board bring-up

1. A serial console and JTAG/SWD on the PCB (test points and a Tag-Connect footprint). OpenOCD configs for the SoC; probe-rs for the MCUs.
2. A USB-C gadget: CDC-NCM for SSH and gdbserver, `ums` and fastboot in U-Boot, and the ROM recovery path documented.
3. Profiling baseline: perf, ftrace and trace-cmd, samply and Tracy against UI and audio latency targets.
4. HAT firmware builds: HackRF (CMake, arm-none-eabi-gcc, iCE40 gateware with Amaranth) and NanoVNA (legacy GCC container).

### Production

1. Secure boot: HABv4 with CST (i.MX), or OTP key hash with signed TPL, SPL and FIT (Rockchip). RP2350 signing through picotool. A key-management process, with an HSM or offline keys.
2. Factory provisioning station (Linux) running uuu or rockusb scripts, MCU flashing through probe-rs or picotool, and test fixtures driven by labgrid.
3. Crash collection (systemd-coredump or minidumps) and symbol storage for each release.
4. Reproducibility audit: rebuild an image from a tag and compare hashes.

---

## Host install table (recommendations)

| Tool | macOS (Apple Silicon) | Linux | Container instead? | Phase |
|---|---|---|---|---|
| rustup + targets (`aarch64-unknown-linux-{gnu,musl}`, `thumbv6m-none-eabi`, `thumbv8m.main-none-eabihf`, `riscv32imac-unknown-none-elf`) | rustup | rustup | Also in the build image | Now |
| mise (pins everything else) | brew / installer | installer | n/a | Now |
| Linux VM or container runtime (Lima, OrbStack, Docker or Apple `container`) | Yes | Docker or Podman | n/a | Now |
| cargo-zigbuild + zig 0.15.2 | mise | mise | Optional | Now |
| cargo-nextest, cargo-deny, cargo-binstall | mise | mise | Yes | Now |
| probe-rs-tools 0.32 (probe-rs, cargo-embed) | mise or installer | mise or installer, plus udev rules | No (USB) | Now |
| picotool 2.3.1 | brew | distro or source | No (USB) | Now |
| dfu-util | brew | distro | No (USB) | Now |
| OSS CAD Suite (dated) | tarball | tarball | Also in CI image | Now |
| QEMU 11.1 / UTM 5.0.8 | brew qemu (2D) + UTM (GL) | distro QEMU + virglrenderer | No (display) | Now |
| Serial terminal (tio or picocom) | brew | distro | No | Now |
| Tracy GUI 0.14.1, samply 0.13.1 | brew or release | release | No (GUI) | Bring-up |
| LLDB (Xcode CLT or brew `llvm`) / gdb-multiarch | Yes | distro | Also in container | Bring-up |
| OpenOCD (0.12 or git) | brew | distro | No (USB) | Bring-up |
| Arm GNU Toolchain 15.2 (`arm-none-eabi-gdb`) | pkg or tarball | tarball | Legacy GCC 8 for NanoVNA: **container only** | Bring-up |
| bmaptool 3.9 | pipx (raw-disk use **UNVERIFIED**) | distro or pipx | No (block devices) | Once SoC chosen |
| uuu 1.5.243 (i.MX) | brew | distro `mfgtools` | No (USB) | Once SoC chosen |
| rockusb 0.4 / rkdeveloptool (Rockchip) | cargo / source | cargo / distro | No (USB) | Once SoC chosen |
| labgrid client 26.0 | pipx (**UNVERIFIED** on macOS) | pipx | Exporter on lab host | Once SoC chosen |
| mmdebstrap / debos / mkosi / alpine-make-rootfs | **No**: use the container or VM | distro | **Yes, preferred** | Once SoC chosen |
| Debian or Alpine sysroot and `-dev` packages | **No** | optional | **Yes**: build image | Now |
| NXP CST / Rockchip signing tools | No | Lab or offline signing host only | Isolated | Production |

---

## Main open questions to confirm

1. Which kernel 7+ packages Debian (backports or testing) and Alpine ship for arm64, and whether they enable the SoC drivers needed (display, audio codec, GPU) without custom builds.
2. How deep STM32U0 support goes in Embassy and probe-rs. Verify on hardware.
3. Whether the GitHub arm64 runners have KVM, which decides whether debos and fast QEMU run in hosted CI.
4. RK3576: blob count (BL31, DDR, no OP-TEE) compared with RK3566 and i.MX 8M Plus. This feeds the SoC decision.
5. A GL-accelerated QEMU path on macOS for a scripted workflow (UTM compared with waiting for upstream Venus on macOS).
