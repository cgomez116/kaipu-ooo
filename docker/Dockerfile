# kaipu-ooo Vivado build container
# ============================================================
# SETUP (one-time):
#   1. Download "Vivado ML Standard - Linux Self Extracting Web Installer"
#      (~1.5 GB) from https://www.xilinx.com/support/download.html
#      Save as: docker/FPGAs_AdaptiveSoCs_Unified_SDI_<ver>_Lin64.bin
#
#   2. Put your AMD account credentials in two local files
#      (these are .gitignored, never committed):
#        echo "your@email.com" > docker/.amd_user
#        echo "yourpassword"   > docker/.amd_pass
#
#   3. make docker-build        (~25-35 GB download, ~60 min first time)
#
# USAGE (every build):
#   make docker-bit
# ============================================================
FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Vivado runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libncurses5 \
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

# Copy the web installer and config
COPY FPGAs_AdaptiveSoCs_Unified_*.bin /tmp/installer.bin
COPY install_config.txt               /tmp/install_config.txt

# Run the installer. AMD credentials are injected via BuildKit secrets
# (--secret id=amd_user / amd_pass) and are NOT stored in the image or
# any layer. The installer uses them only to authenticate the download.
RUN --mount=type=secret,id=amd_user \
    --mount=type=secret,id=amd_pass \
    chmod +x /tmp/installer.bin && \
    AMD_USER=$(cat /run/secrets/amd_user) && \
    AMD_PASS=$(cat /run/secrets/amd_pass) && \
    cp /tmp/install_config.txt /tmp/install_config_auth.txt && \
    echo "User=${AMD_USER}"     >> /tmp/install_config_auth.txt && \
    echo "Password=${AMD_PASS}" >> /tmp/install_config_auth.txt && \
    /tmp/installer.bin \
        -- \
        --agree XilinxEULA,3rdPartyEULA \
        --batch Install \
        --config /tmp/install_config_auth.txt \
    && rm /tmp/installer.bin /tmp/install_config_auth.txt

ENV PATH="/tools/Xilinx/Vivado/2026.1/bin:${PATH}"

WORKDIR /work
