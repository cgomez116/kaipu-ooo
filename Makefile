SHELL := bash
.SECONDEXPANSION:

VENDOR := vendor/kaipu
TOOLS  := $(VENDOR)/tools

# PROG selects the .asm firmware source.  Default: looping (safe no-op).
# Override: make nexys_a7_bitstream PROG=vendor/kaipu/tests/programs/foo.asm
PROG     ?= $(VENDOR)/tests/programs/looping.asm
PROG_HEX := $(PROG:.asm=.hex)

VIVADO       ?= vivado
DOCKER_IMAGE ?= kaipu-vivado
BITSTREAM    := synth/nexys_a7/top.bit

# Nexys A7-100T Digilent device name (djtgcfg probe to confirm yours)
DIGILENT_DEV ?= Nexys A7-100T

# ---------------------------------------------------------------------------
# Firmware: assemble → hex → split into lo/hi banks
# ---------------------------------------------------------------------------
%.hex: %.asm
	python3 $(TOOLS)/asm.py -o $@ -l $(@:.hex=.lst) \
	    $(TOOLS)/layout/basic.asm $<

program.hex: $(PROG_HEX)
	cp $< $@

program_lo.hex: program.hex $(TOOLS)/split_hex.py
	python3 $(TOOLS)/split_hex.py program.hex program_lo.hex program_hi.hex
program_hi.hex: program_lo.hex ;

# ---------------------------------------------------------------------------
# Bitstream: native Vivado (Linux/CI)
# ---------------------------------------------------------------------------
.PHONY: nexys_a7_bitstream
nexys_a7_bitstream: program_lo.hex program_hi.hex
	mkdir -p synth/nexys_a7
	$(VIVADO) -mode batch -source vivado/build_top.tcl \
	    -log synth/nexys_a7/vivado_build.log \
	    -journal synth/nexys_a7/vivado_build.jou

.PHONY: bit
bit: nexys_a7_bitstream

# ---------------------------------------------------------------------------
# Docker build flow (Mac-native path)
# ---------------------------------------------------------------------------
# Step 1 (one-time, ~45 min):
#   Download Vivado ML Standard Linux installer to docker/
#   then: make docker-build
#
# Step 2 (every build):
#   make docker-bit
#
# Step 3 (after board is connected):
#   make flash

.PHONY: docker-build
docker-build:
	@echo "Building kaipu-vivado Docker image (~35 GB, ~45 min first time)..."
	@test -n "$$(ls docker/Xilinx_Unified_*.bin 2>/dev/null)" || \
	    { echo "ERROR: download the Vivado ML Standard Linux installer to docker/ first"; exit 1; }
	docker build -t $(DOCKER_IMAGE) docker/

# Run the Vivado build inside the container.
# Mounts the repo root at /work so the container can read sources and write
# synth/nexys_a7/top.bit back to the host filesystem.
.PHONY: docker-bit
docker-bit: program_lo.hex program_hi.hex
	mkdir -p synth/nexys_a7
	docker run --rm \
	    -v "$(CURDIR):/work" \
	    -w /work \
	    $(DOCKER_IMAGE) \
	    make nexys_a7_bitstream

# ---------------------------------------------------------------------------
# Flash (macOS — uses Digilent Adept djtgcfg, no Vivado needed)
# ---------------------------------------------------------------------------
# Install Adept: https://digilent.com/reference/software/adept/start
# Confirm device name: djtgcfg enum
.PHONY: flash
flash: $(BITSTREAM)
	djtgcfg prog -d "$(DIGILENT_DEV)" -i 0 -f $(BITSTREAM)

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
	@echo "Mac-native workflow:"
	@echo "  1. Download Vivado installer to docker/, then: make docker-build"
	@echo "  2. make docker-bit [PROG=path/to/foo.asm]"
	@echo "  3. make flash                  (board connected via USB)"
	@echo ""
	@echo "Linux/CI workflow:"
	@echo "  make nexys_a7_bitstream [PROG=path/to/foo.asm]"
	@echo "  make flash"
	@echo ""
	@echo "Other:"
	@echo "  make submodule-update          Init/update vendor/kaipu"
	@echo "  make docker-build              Build Vivado Docker image (one-time)"
