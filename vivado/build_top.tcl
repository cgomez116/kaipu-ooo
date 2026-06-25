# Vivado non-project build script for kaipu-ooo basic-tier top.
# Target: XC7A100TCSG324-1 (Nexys A7-100T)
# Usage (from repo root):
#   vivado -mode batch -source vivado/build_top.tcl
#
# kaipu HDL uses backtick `include chains (top.v -> cpu_top.v -> pipeline.v
# -> cells.v, l1i_cache.v, ...).  Vivado follows `include automatically when
# given the right include directories; we therefore read ONLY the entry-point
# top.v — never the included files separately — to avoid duplicate-module
# elaboration errors.
#
# Outputs in synth/nexys_a7/:
#   top.bit                — bitstream (flash via Vivado HW Manager in user terminal)
#   top.dcp                — post-route checkpoint
#   timing_summary.rpt     — timing closure report
#   utilization.rpt        — LUT / BRAM / DSP resource report

set ROOT   [file normalize [file dirname [file dirname [info script]]]]
set VENDOR $ROOT/vendor/kaipu
set OUTDIR $ROOT/synth/nexys_a7
file mkdir $OUTDIR

# ---------------------------------------------------------------------------
# Include directories — Vivado resolves `include paths from this list
# ---------------------------------------------------------------------------
set INC_DIRS [list \
    $VENDOR/hdl \
    $VENDOR/hdl/axi \
    $VENDOR/hdl/frontend \
    $VENDOR/hdl/decode \
    $VENDOR/hdl/execute \
    $VENDOR/hdl/lsu \
    $VENDOR/hdl/mem \
    $VENDOR/hdl/shared \
    $ROOT/fpga/nexys_a7 \
]

# ---------------------------------------------------------------------------
# Read sources — ONLY the entry-point top.v (include chain pulls the rest).
# pll_20.v and cpu_top.v are reached via `include inside top.v.
# ---------------------------------------------------------------------------
read_verilog $ROOT/fpga/nexys_a7/top.v

# Constraints
read_xdc $ROOT/fpga/nexys_a7/nexys_a7_basic.xdc

# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------
synth_design \
    -top top \
    -part xc7a100tcsg324-1 \
    -include_dirs $INC_DIRS \
    -verilog_define FPGA_SYNTH \
    -verilog_define RAM_SYNC_READ \
    -flatten_hierarchy rebuilt

write_checkpoint -force $OUTDIR/post_synth.dcp
report_utilization -file $OUTDIR/utilization_synth.rpt

# ---------------------------------------------------------------------------
# Implementation
# ---------------------------------------------------------------------------
opt_design
place_design
phys_opt_design
route_design

report_timing_summary -max_paths 10 -file $OUTDIR/timing_summary.rpt
report_utilization                  -file $OUTDIR/utilization.rpt

write_checkpoint -force $OUTDIR/top.dcp
write_bitstream   -force $OUTDIR/top.bit

puts ""
puts "=== kaipu-ooo nexys_a7 build complete ==="
puts "Bitstream : $OUTDIR/top.bit"
puts "Flash via Vivado HW Manager (run in a separate terminal):"
puts "  open_hw_manager"
puts "  connect_hw_server"
puts "  open_hw_target"
puts "  program_hw_devices [get_hw_devices xc7a100t_0] -bitfile $OUTDIR/top.bit"
