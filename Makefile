SHELL := bash
.SECONDEXPANSION:

VENDOR := vendor/kaipu
TOOLS  := $(VENDOR)/tools

# PROG selects the .asm firmware source.  Default: looping (safe no-op).
# Override: make nexys_a7_bitstream PROG=vendor/kaipu/tests/programs/foo.asm
PROG     ?= $(VENDOR)/tests/programs/looping.asm
PROG_HEX := $(PROG:.asm=.hex)

VIVADO   ?= vivado

# ---------------------------------------------------------------------------
# Firmware: assemble → hex → split into lo/hi banks
# ---------------------------------------------------------------------------
# Invoke kaipu's assembler; layout/basic.asm is the crt0 for C-derived asm.
%.hex: %.asm
	python3 $(TOOLS)/asm.py -o $@ -l $(@:.hex=.lst) \
	    $(TOOLS)/layout/basic.asm $<

# Copy selected firmware to program.hex (Vivado reads program_{lo,hi}.hex).
program.hex: $(PROG_HEX)
	cp $< $@

# Split into even/odd 16-bit banks (matches axi4_mem.v dual-bank layout).
program_lo.hex: program.hex $(TOOLS)/split_hex.py
	python3 $(TOOLS)/split_hex.py program.hex program_lo.hex program_hi.hex
program_hi.hex: program_lo.hex ;

# ---------------------------------------------------------------------------
# Bitstream: Vivado non-project flow
# ---------------------------------------------------------------------------
.PHONY: nexys_a7_bitstream
nexys_a7_bitstream: program_lo.hex program_hi.hex
	$(VIVADO) -mode batch -source vivado/build_top.tcl \
	    -log synth/nexys_a7/vivado_build.log \
	    -journal synth/nexys_a7/vivado_build.jou

# Convenience alias
.PHONY: bit
bit: nexys_a7_bitstream

# ---------------------------------------------------------------------------
# Submodule helpers
# ---------------------------------------------------------------------------
.PHONY: submodule-update
submodule-update:
	git submodule update --init --recursive

.PHONY: vendor-bump
vendor-bump:
	@echo "Usage: git -C vendor/kaipu fetch origin && git -C vendor/kaipu checkout <sha>"
	@echo "       git add vendor/kaipu && git commit -m 'vendor: bump kaipu to <sha> (<reason>)'"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
.PHONY: help
help:
	@echo "Targets:"
	@echo "  nexys_a7_bitstream  Build top.bit for Nexys A7-100T (Vivado)"
	@echo "  bit                 Alias for nexys_a7_bitstream"
	@echo "  program.hex         Assemble firmware (PROG=path/to/foo.asm)"
	@echo "  submodule-update    Init/update vendor/kaipu submodule"
