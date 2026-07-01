SHELL := bash
.SECONDEXPANSION:

VENDOR := vendor/kaipu
TOOLS  := $(VENDOR)/tools

# PROG selects the .asm firmware source.  Default: looping (safe no-op).
# Override: make nexys_a7_bitstream PROG=vendor/kaipu/tests/programs/foo.asm
PROG     ?= $(VENDOR)/tests/programs/looping.asm
PROG_HEX := $(PROG:.asm=.hex)

VIVADO          ?= vivado
DOCKER_IMAGE    ?= kaipu-vivado
# Vivado lives here inside the container (installer path, not the classic
# .../Vivado/<ver>/bin layout). Injected at runtime so the flow works even
# against an image built before the Dockerfile PATH was corrected.
VIVADO_BIN      ?= /tools/Xilinx/2026.1/Vivado/bin
CONTAINER_PATH  := $(VIVADO_BIN):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# The free "Vivado Basic Tier" license is node-locked to a host ID = MAC.
# Containers get a random MAC per run, so we pin it; docker/Xilinx.lic must be
# generated against this exact address (see docker/README / AMD licensing portal).
VIVADO_MAC      ?= 02:42:ac:11:00:02
VIVADO_LIC      := docker/Xilinx.lic
# Docker Desktop on macOS places the socket at ~/.docker/run/docker.sock.
# The /var/run/docker.sock symlink may be absent after a reset; fall back here.
DOCKER_SOCK     := $(shell [ -S /var/run/docker.sock ] && echo unix:///var/run/docker.sock || echo unix://$(HOME)/.docker/run/docker.sock)
export DOCKER_HOST ?= $(DOCKER_SOCK)
BITSTREAM       := synth/nexys_a7/top.bit
OFL             ?= ~/Documents/FPGA_TOOLS/oss-cad-suite/bin/openFPGALoader

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
# Step 1 (one-time, ~2 min):
#   Download web installer (~1.5 GB) to docker/
#   make docker-auth-token   ← interactive; prompts for AMD email + password
#
# Step 2 (one-time, ~45 min):
#   make docker-build
#
# Step 3 (every build):
#   make docker-bit
#
# Step 4 (after board is connected):
#   make flash

# Generate an AMD auth token required by the 2026.1+ web installer.
# Runs xsetup -b AuthTokenGen inside a temporary container (interactive —
# you will be prompted for your AMD account email and password).
# Re-run if the token expires and docker-build starts failing with auth errors.
.PHONY: docker-auth-token
docker-auth-token:
	@echo "Generating AMD auth token (you will be prompted for your AMD email + password)..."
	@mkdir -p "$(HOME)/.Xilinx/xinstall"
	docker run --rm -it \
	    --platform linux/amd64 \
	    -v "$(CURDIR)/docker:/installer:ro" \
	    -v "$(HOME)/.Xilinx:/root/.Xilinx" \
	    ubuntu:22.04 bash -c " \
	        apt-get update -qq && apt-get install -y -qq ca-certificates && \
	        cp /installer/FPGAs_AdaptiveSoCs_Unified_*.bin /tmp/installer.bin && \
	        chmod +x /tmp/installer.bin && \
	        /tmp/installer.bin -- -b AuthTokenGen \
	    "
	@cp "$(HOME)/.Xilinx/wi_authentication_key" docker/.amd_token
	@echo "Token saved to docker/.amd_token  (gitignored; re-run this target when it expires)"

# Dump the full install config template for this installer version.
# Use this to discover valid Edition/Product/Modules names, then update
# docker/install_config.txt to restrict the download to Vivado-only (~8 GB)
# instead of the full Vitis platform (~32 GB).
.PHONY: docker-config-gen
docker-config-gen:
	@echo "Generating installer config template → /tmp/xilinx-configgen/install_config.txt ..."
	@mkdir -p /tmp/xilinx-configgen
	docker run --rm -it \
	    --platform linux/amd64 \
	    -v "$(CURDIR)/docker:/installer:ro" \
	    -v "/tmp/xilinx-configgen:/config" \
	    -v "$(HOME)/.Xilinx:/root/.Xilinx" \
	    ubuntu:22.04 bash -c " \
	        apt-get update -qq && apt-get install -y -qq ca-certificates && \
	        cp /installer/FPGAs_AdaptiveSoCs_Unified_*.bin /tmp/installer.bin && \
	        chmod +x /tmp/installer.bin && \
	        /tmp/installer.bin -- -b ConfigGen -l /config \
	    "
	@echo ""
	@echo "Config template written to /tmp/xilinx-configgen/"
	@ls /tmp/xilinx-configgen/

.PHONY: docker-build
docker-build:
	@echo "Building kaipu-vivado Docker image (~25-35 GB download, ~60 min)..."
	@test -n "$$(ls docker/FPGAs_AdaptiveSoCs_Unified_*.bin 2>/dev/null)" || \
	    { echo "ERROR: download the Vivado web installer to docker/ first"; exit 1; }
	@test -f docker/.amd_token || \
	    { echo "ERROR: run 'make docker-auth-token' first to generate docker/.amd_token"; exit 1; }
	DOCKER_BUILDKIT=1 docker build \
	    --load \
	    --platform linux/amd64 \
	    --secret id=amd_token,src=docker/.amd_token \
	    -t $(DOCKER_IMAGE) docker/

# Run the Vivado build inside the container.
# Mounts the repo root at /work so the container can read sources and write
# synth/nexys_a7/top.bit back to the host filesystem.
#
# Running Vivado 2026.1 x86-64 under emulation on Apple Silicon needs several
# workarounds (all no-ops once the image is rebuilt from the current Dockerfile):
#   --mac-address  pins the host ID the node-locked license is bound to.
#   Xilinx.lic     mounted read-only; XILINXD_LICENSE_FILE points Vivado at it.
#   PATH           injected because older images baked the wrong Vivado path.
#   libpixman-1-0  Vivado's libxv_tcltasks.so needs it; slim base lacks it.
#   rm libudev     FlexLM's udev dongle scan corrupts the heap under emulation
#                  ("realloc(): invalid pointer"); removing libudev makes it skip
#                  the scan and fall back to the (MAC) host-ID license. Install
#                  pixman FIRST — apt itself depends on libudev.
.PHONY: docker-bit
docker-bit: program_lo.hex program_hi.hex
	@test -f "$(VIVADO_LIC)" || { \
	    echo "ERROR: $(VIVADO_LIC) missing. Generate a free 'Vivado Basic Tier'"; \
	    echo "node-locked license for host ID $(subst :,,$(VIVADO_MAC)) at the AMD"; \
	    echo "licensing portal and save it there (see docker/ notes)."; exit 1; }
	mkdir -p synth/nexys_a7
	docker run --rm \
	    --platform linux/amd64 \
	    --mac-address $(VIVADO_MAC) \
	    -v "$(CURDIR):/work" \
	    -w /work \
	    -v "$(CURDIR)/$(VIVADO_LIC):/root/.Xilinx/Xilinx.lic:ro" \
	    -e XILINXD_LICENSE_FILE=/root/.Xilinx/Xilinx.lic \
	    -e PATH="$(CONTAINER_PATH)" \
	    $(DOCKER_IMAGE) \
	    bash -c "dpkg -s libpixman-1-0 >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq libpixman-1-0; }; \
	             rm -f /lib/x86_64-linux-gnu/libudev.so.1* /usr/lib/x86_64-linux-gnu/libudev.so.1* 2>/dev/null; \
	             make nexys_a7_bitstream"

# ---------------------------------------------------------------------------
# Flash (macOS — openFPGALoader from oss-cad-suite, no Vivado needed)
# ---------------------------------------------------------------------------
# Nexys A7 uses an FT2232H onboard JTAG (Digilent HS2-compatible).
# openFPGALoader is already in oss-cad-suite; no extra install needed.
# If the board isn't detected, try: $(OFL) --detect
.PHONY: flash
flash: $(BITSTREAM)
	$(OFL) -c digilent_hs2 $(BITSTREAM)

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
	@echo "  1. Download web installer (~1.5 GB) to docker/"
	@echo "  2. make docker-auth-token  (interactive, one-time — prompts for AMD credentials)"
	@echo "  3. make docker-build       (~25-35 GB download, ~60 min, one-time)"
	@echo "  4. make docker-bit         # produces synth/nexys_a7/top.bit"
	@echo "  5. make flash              # openFPGALoader (already in oss-cad-suite)"
	@echo ""
	@echo "Linux/CI workflow:"
	@echo "  make nexys_a7_bitstream [PROG=path/to/foo.asm]"
	@echo "  make flash"
	@echo ""
	@echo "Other:"
	@echo "  make submodule-update          Init/update vendor/kaipu"
	@echo "  make docker-build              Build Vivado Docker image (one-time)"
