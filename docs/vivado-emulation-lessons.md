# Lessons Learned: Vivado 2026.1 Bitstream Builds on Apple Silicon

Running the AMD Vivado 2026.1 toolchain (x86-64 only) inside Docker on an Apple
Silicon Mac to build `synth/nexys_a7/top.bit` for the Nexys A7-100T
(XC7A100TCSG324-1). First successful bitstream: **2026-06-30**.

Everything below is now automated by `make docker-bit` and baked into
`docker/Dockerfile`. This document explains *why* each piece is there so the
workarounds aren't mistaken for cargo-cult and accidentally removed.

## TL;DR — the working flow

```sh
make docker-build      # one-time: build the image (~60 min, ~30 GB download)
make docker-bit        # every build: synth → place → route → top.bit (~15 min emulated)
make flash             # board connected: openFPGALoader, no Vivado needed
```

Prerequisites captured once: the Vivado web installer + AMD auth token in
`docker/`, and a node-locked `docker/Xilinx.lic` (see Lesson 4).

## The debugging chain

Seven distinct failures stood between "run the container" and a bitstream. Each
looked like the last one until it wasn't.

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | Every `docker` command hangs | Virtual disk full (`no space left on device`) | Raise Docker Desktop disk limit; **never** `docker system prune -a` (deletes the 29 GB image) |
| 2 | `vivado: command not found` | Installer path is `/tools/Xilinx/2026.1/Vivado/bin`, not the classic `.../Vivado/<ver>/bin` | Correct `PATH` |
| 3 | `locale::facet::_S_create_c_locale` abort | `en_US.UTF-8` absent; `rdiArgs.sh` hardcodes it (so `LC_ALL=C.UTF-8` can't help) | `locale-gen en_US.UTF-8` in the image |
| 4 | "a valid license was not found" | 2026.1 Standard/"Basic Tier" requires a license file even for free 7-series parts | Node-locked free license, MAC-pinned (below) |
| 5 | `realloc(): invalid pointer`, abort in license checkout | FlexLM's `libudev` USB-dongle scan corrupts glibc's heap **under emulation** | **Delete `libudev.so.1`** (below) |
| 6 | `libpixman-1.so.0: cannot open shared object` | Slim Ubuntu base lacks it; Vivado's `libxv_tcltasks.so` needs it | `apt-get install libpixman-1-0` |
| 7 | `write_bitstream` DRC: VCO 4000 MHz out of range | **Real RTL bug** — PLL configured for a 25 MHz input; the board oscillator is 100 MHz | `pll_20.v`: `CLKFBOUT_MULT_F` 40 → 10 |

## Lesson 4 — the license is node-locked to a MAC, and containers randomize it

Vivado 2026.1's free tier is now **"Vivado Basic Tier"** (successor to WebPACK /
ML Standard). It covers the XC7A100T, but unlike older WebPACK it is **not
license-free** — you must generate a node-locked `.lic` from the AMD licensing
portal. The lock is a host ID derived from the **network MAC address**.

A Docker container gets a *random* MAC per run, which would invalidate the
license every build. So `make docker-bit` pins it:

```
--mac-address 02:42:ac:11:00:02        →  host ID 0242ac110002
```

`docker/Xilinx.lic` (gitignored) is generated against exactly that host ID.
If the pinned MAC ever changes, regenerate the license at the AMD portal.

## Lesson 5 — the libudev heap crash was the real wall

This one burned the most time. FlexLM (`libXil_lmgr11.so`) enumerates hardware
via `libudev` to look for USB license dongles. Under QEMU **and** under
Apple-Virtualization + Rosetta, `udev_enumerate_scan_devices()` corrupts glibc's
heap and the process aborts with `realloc(): invalid pointer` — *during license
checkout*, before Vivado even reads the TCL.

What did **not** work, and why:
- `MALLOC_CHECK_=0` — the abort is via glibc's `malloc_printerr`, which ignores it.
- Switching Docker to Rosetta — faster/more faithful, but the crash is in
  libudev's own logic, not a TCG codegen bug, so it reproduced identically.
- `LD_PRELOAD` shim / `/etc/ld.so.preload` stubbing `udev_enumerate_scan_devices`
  — **FlexLM `dlopen`s `libudev.so.1` by name and `dlsym`s the symbol directly**,
  so symbol interposition never gets a look-in.

What worked: **remove `libudev.so.1` entirely.** FlexLM's `dlopen` then fails
gracefully, it skips dongle detection, and checkout falls back to the
MAC-derived node-locked host ID — which is exactly what we want. Caveat: `apt`
depends on libudev, so any package installs must happen *before* the removal.

`docker/udev_stub.c` (the failed LD_PRELOAD approach) is kept as a documented
dead end.

## Lesson 7 — the tooling failure was hiding a real design bug

The `pll_20.v` MMCM was ported from an ECP5 board with a 25 MHz input
(`CLKFBOUT_MULT_F=40`, `CLKIN1_PERIOD=40`). The Nexys A7 oscillator is **100 MHz**
(E3, 10 ns, per the XDC). Feeding 100 MHz into a ×40 multiplier gives a 4000 MHz
VCO — 3.3× over the Artix-7 limit of 600–1200 MHz. It surfaced as a
CRITICAL WARNING during `place_design` and a hard DRC error at `write_bitstream`.

Fix: `CLKFBOUT_MULT_F` 40 → 10, `CLKIN1_PERIOD` 40 → 10 (VCO = 100 × 10 =
1000 MHz, output still 1000/50 = 20 MHz). This also *closed timing* — WNS went
from −2.4 ns to +20.6 ns, because the bogus VCO had been poisoning the analysis.

## Environment notes

- **Docker Desktop**: Apple Virtualization framework + "Use Rosetta for x86-64
  emulation" (Settings → General). Docker VMM falls back to QEMU TCG.
- A full `make docker-bit` runs ~15 min under emulation; native x86-64 Linux
  would be far faster if wall-clock ever matters.
- **Not yet validated on hardware.** Because of bug #7, no bitstream had ever
  reached the board before this build. If the design misbehaves on-board, start
  with the L1D-cache-FSM critical paths in `synth/nexys_a7/timing_summary.rpt`.
