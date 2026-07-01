<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="vendor/kaipu/docs/diagrams/kaipu-logo-dark.svg">
    <img alt="kaipu-ooo" src="vendor/kaipu/docs/diagrams/kaipu-logo.svg" width="200">
  </picture>
</p>

# kaipu-ooo

Out-of-order sibling of [kaipu](https://github.com/cgomez116/kaipu). Targets the Digilent Nexys A7-100T (Artix-7 XC7A100T, ~63K LUT6, 128 MB DDR2) using Vivado. Both projects implement the **kaisa ISA** — comparative IPC across the same instruction set is the headline result.

For the fork rationale and sharing strategy, see [ADR-0025](https://github.com/cgomez116/kaipu/blob/main/docs/adr/0025-kaipu-ooo-fork-strategy.md) in the kaipu repo.

## Status

Bootstrapped 2026-06-25. No RTL yet. `vendor/kaipu` submodule pinned; greenfield CPU core work begins next.

## Repository layout

```
vendor/kaipu/     shared substrate (ISA spec, tools, ISS, tests, uncore IP)
hdl/core/         OoO pipeline — frontend, rename, IQ, ROB, LSQ, commit
hdl/l1/           L1 caches (MSHRs, speculative fills, squash)
hdl/mmu/          MMU/TLB (concurrent walker, multi-port)
hdl/bp/           branch predictor (TAGE-class)
fpga/             Nexys A7 board glue, constraints, DDR2 controller
vivado/           Vivado project scripts
```

## What's shared with kaipu

| Layer | Mechanism |
|---|---|
| kaisa ISA spec | `vendor/kaipu/docs/ISA_spec.md` (submodule) |
| Assembler, rv2kaisa, layout files | `vendor/kaipu/tools/` (submodule) |
| ISS (lockstep cosim oracle) | `vendor/kaipu/iss/` (submodule) |
| Verification corpus | `vendor/kaipu/tests/` (submodule) |
| Uncore IP (UART, GPIO, CLINT, PLIC, SDRAM, AXI fabric, L2, MMIO crossbar) | `vendor/kaipu/hdl/uncore/` (submodule) |

## What's greenfield here

L1 caches (OoO needs MSHRs + speculative fills + squash), MMU/TLB (concurrent walker, multi-port TLB), branch predictor (TAGE-class), the OoO core itself, and the Vivado/Nexys A7 FPGA flow.

## Getting started

```sh
git clone --recurse-submodules https://github.com/cgomez116/kaipu-ooo.git
cd kaipu-ooo
# vendor/kaipu is the shared substrate — tools, ISS, and tests all live there
```

## FPGA build (Nexys A7-100T)

The Vivado bitstream flow runs the AMD toolchain in Docker — including x86-64
emulation on Apple Silicon:

```sh
make docker-build      # one-time: build the Vivado image
make docker-bit        # synth → place → route → synth/nexys_a7/top.bit
make flash             # board connected: flash via openFPGALoader
```

Getting Vivado 2026.1 to build under emulation took seven distinct fixes
(licensing, a libudev heap crash, a real PLL bug, and more). See
[docs/vivado-emulation-lessons.md](docs/vivado-emulation-lessons.md) for the
full debugging chain and why each workaround exists.
