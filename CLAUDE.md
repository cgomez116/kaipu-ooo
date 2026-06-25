# CLAUDE.md

This file is read by Claude Code and other agents working in the kaipu-ooo repo.

`kaipu-ooo` is the out-of-order sibling of [kaipu](https://github.com/cgomez116/kaipu). It targets the Digilent Nexys A7-100T (Artix-7 XC7A100T, ~63K LUT6, 128 MB DDR2) using the Vivado toolchain. The headline result is **comparative IPC on the kaisa ISA** — not Linux. See [ADR-0025](https://github.com/cgomez116/kaipu/blob/main/docs/adr/0025-kaipu-ooo-fork-strategy.md) for the full fork strategy.

## Shared substrate

All shared material lives in `vendor/kaipu/` (git submodule, pinned). **Never modify files under `vendor/kaipu/` directly** — changes to the shared substrate go upstream to kaipu via PR there, then a submodule bump here.

Shared (via submodule):
- `vendor/kaipu/docs/ISA_spec.md` — kaisa ISA specification (inter-repo contract)
- `vendor/kaipu/tools/` — asm.py, rv2kaisa, layout files
- `vendor/kaipu/iss/` — ISS for lockstep cosim
- `vendor/kaipu/tests/` — verification corpus (asm, fuzz, regression)
- `vendor/kaipu/hdl/uncore/` — UART, GPIO, CLINT, PLIC, SDRAM controller, AXI fabric, L2, MMIO crossbar

Greenfield here:
- `hdl/core/` — OoO frontend, rename, IQ, ROB, LSQ, commit
- `hdl/l1/` — L1 caches (MSHRs, speculative fills, squash — re-implemented for OoO)
- `hdl/mmu/` — MMU/TLB (concurrent walker, multi-port)
- `hdl/bp/` — branch predictor (TAGE-class)
- `fpga/` — Nexys A7 board glue, constraints, DDR2 controller
- `vivado/` — project scripts

## Bumping the submodule

```sh
git -C vendor/kaipu fetch origin && git -C vendor/kaipu checkout <new-sha>
git add vendor/kaipu
git commit -m "vendor: bump kaipu to <short-sha> (<reason>)"
```

## kaisa conformance gate

Any PR touching the ISA spec or its decoders must pass the kaisa conformance suite in **both** repos before merge. Currently enforced implicitly via differential cosim against the kaipu ISS (`vendor/kaipu/iss/`). Formalizing this as a CI gate is a follow-up once this repo has CI.

## Worktrees

Same discipline as kaipu: one worktree per concurrent stream. New streams: `git worktree add -b <branch> .claude/worktrees/<stream> main`.
