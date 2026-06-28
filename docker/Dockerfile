# kaipu-ooo Vivado build container
# ============================================================
# SETUP (one-time):
#   1. Download "FPGAs_AdaptiveSoCs_Unified_*_Lin64.bin"
#      (~1.5 GB) from https://www.xilinx.com/support/download.html
#      Save as: docker/FPGAs_AdaptiveSoCs_Unified_<ver>_Lin64.bin
#
#   2. Generate an AMD auth token (interactive — prompts for credentials):
#        make docker-auth-token
#      Saves token to docker/.amd_token (gitignored).
#      Re-run this step if docker-build later fails with an auth error.
#
#   3. make docker-build        (~10 GB download, ~90 min first time)
#
# USAGE (every build):
#   make docker-bit
#
# ============================================================
# HARD-WON INSTALLER FACTS (2026.1 unified installer):
#
# Edition:   Must be "Vivado Design Suite" — NOT "Vitis Unified Software
#            Platform". The wrong edition downloads 32 GB of Vitis + AIE
#            tools that Artix-7 doesn't support. Confirmed via ConfigGen.
#
# Auth:      --user/--pw CLI flags were removed in 2026.1. The token file
#            is ~/.Xilinx/wi_authentication_key (NOT xinstall/xauth.token).
#            Generate with: make docker-auth-token (runs xsetup AuthTokenGen).
#
# Docker:    macOS Docker Desktop socket lives at ~/.docker/run/docker.sock,
#            not /var/run/docker.sock. After a reset the symlink may be gone;
#            the Makefile detects and falls back automatically.
#            --load is required when using the docker-container buildx driver.
#            Increase Docker Desktop memory to ≥16 GB — the Java installer
#            OOM-kills below that threshold.
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

# Run the installer. The AMD auth token is injected via BuildKit secret
# (--secret id=amd_token) and is NOT stored in the image or any layer.
# Generate the token first with:  make docker-auth-token
RUN --mount=type=secret,id=amd_token \
    chmod +x /tmp/installer.bin && \
    mkdir -p /root/.Xilinx && \
    cp /run/secrets/amd_token /root/.Xilinx/wi_authentication_key && \
    /tmp/installer.bin \
        -- \
        --agree XilinxEULA,3rdPartyEULA \
        --batch Install \
        --config /tmp/install_config.txt \
    && rm /tmp/installer.bin /root/.Xilinx/wi_authentication_key

ENV PATH="/tools/Xilinx/Vivado/2026.1/bin:${PATH}"

WORKDIR /work
