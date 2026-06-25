# kaipu-ooo Vivado build container
# ============================================================
# SETUP (one-time):
#   1. Download "Vivado ML Standard - Linux Self Extracting Web Installer"
#      from https://www.xilinx.com/support/download.html
#      Save as: docker/Xilinx_Unified_<version>_Lin64.bin
#
#   2. docker build -t kaipu-vivado docker/
#      (~35 GB image, takes ~45 min first time)
#
# USAGE (every build):
#   From repo root:
#     docker run --rm \
#       -v $(pwd):/work \
#       -w /work \
#       kaipu-vivado \
#       make nexys_a7_bitstream
#
# Or just: make docker-bit
# ============================================================
FROM ubuntu:22.04

# Suppress interactive prompts during apt
ENV DEBIAN_FRONTEND=noninteractive

# Vivado runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libncurses5 \
    libncurses5-dev \
    libx11-6 \
    libxext6 \
    libxrender1 \
    libxtst6 \
    libxi6 \
    libfreetype6 \
    libfontconfig1 \
    libtcl8.6 \
    libtk8.6 \
    python3 \
    python3-pip \
    make \
    && rm -rf /var/lib/apt/lists/*

# Copy and run the Vivado installer in batch mode.
# install_config.txt selects only the Artix-7 device family to keep
# the image from ballooning to 100 GB.
COPY Xilinx_Unified_*.bin /tmp/installer.bin
COPY install_config.txt   /tmp/install_config.txt
RUN chmod +x /tmp/installer.bin && \
    /tmp/installer.bin \
        --agree XilinxEULA,3rdPartyEULA \
        --batch Install \
        --config /tmp/install_config.txt \
    && rm /tmp/installer.bin

ENV PATH="/tools/Xilinx/Vivado/2024.2/bin:${PATH}"

WORKDIR /work
