`include "cpu_top.v"
`include "pll_20.v"

// Nexys A7-100T top-level wrapper — free-running kaisa CPU.
// Structural port of vendor/kaipu/fpga/basic/top.v from ULX3S/ECP5 to
// Nexys A7-100T/Artix-7.  Behaviour is identical; only the PLL primitive
// and pin names differ.
//
// btn[0] = BTNC (centre push button) = reset (active-HIGH on Nexys A7).
// LEDs show PC[9:2] of the most recently retired instruction, sampled
// at ~5 Hz so the display is human-readable.
//
// Clocking: 100 MHz board oscillator → 20 MHz CPU clock via MMCME2_ADV
// (fpga/nexys_a7/pll_20.v).  The 100 MHz input feeds the PLL only;
// all sequential logic runs in the 20 MHz domain.
//
// Nexys A7-100T has DDR2 SDRAM (MT47H64M16HR-25E), but that controller
// is out of scope for this first port.  sdram_* ports are left unconnected
// (tied off) so the CPU boots from on-chip BRAM only.
module top #(
    parameter INIT_FILE_BASE = "program",
    parameter MAIN_MEM_DEPTH = 4096,      // 16 KB  (same as basic-tier kaipu)
    parameter L2_CACHE_SIZE  = 16384      // 16 KB  (right-sized to match main mem)
) (
    input  wire        clk_100mhz,        // 100 MHz board oscillator (E3 on Nexys A7)
    input  wire [4:0]  btn,               // BTNC/BTND/BTNL/BTNR/BTNU (active-HIGH)
    output wire [15:0] led                // LD0–LD15 (active-HIGH)
);

    // -----------------------------------------------------------------------
    // PLL: 100 MHz → 20 MHz
    // -----------------------------------------------------------------------
    wire clk_20mhz, pll_locked;
    pll_20 pll (.clk_25mhz(clk_100mhz), .clk_20mhz(clk_20mhz), .locked(pll_locked));
    // Note: the pll_20 port is named clk_25mhz for interface compatibility
    // with the vendor module; here it receives 100 MHz and the MMCM
    // parameters divide appropriately.  See fpga/nexys_a7/pll_20.v.

    // -----------------------------------------------------------------------
    // Reset — BTNC (btn[0]) is the dedicated reset button.
    // Nexys A7 buttons are active-HIGH, so pressed = btn[0] == 1.
    // Same saturating-integrator debounce as the ULX3S port; initial
    // saturation (dbnc = all-ones) holds reset until ~52 ms after PLL lock.
    // -----------------------------------------------------------------------
    reg [1:0]  btn_s;
    reg [19:0] dbnc = {20{1'b1}};
    reg        reset = 1'b1;
    wire       pwr_pressed = btn_s[1];    // active-HIGH: 1 = pressed = hold reset

    always @(posedge clk_20mhz) begin
        btn_s <= {btn_s[0], btn[0]};
        if (pwr_pressed && ~&dbnc)
            dbnc <= dbnc + 1'b1;
        else if (!pwr_pressed && |dbnc)
            dbnc <= dbnc - 1'b1;
        if (&dbnc)
            reset <= 1'b1;
        else if (~|dbnc)
            reset <= 1'b0;
    end

    wire cpu_reset = reset | ~pll_locked;

    // -----------------------------------------------------------------------
    // CPU
    // -----------------------------------------------------------------------
    wire [31:0] debug_pc;
    wire [31:0] retiring_pc;
    wire [5:0]  debug_opcode;
    wire        retire;

    // SDRAM tie-offs (DDR2 controller out of scope for this port).
    wire        sdram_clk_w, sdram_cke_w, sdram_cs_n_w;
    wire        sdram_ras_n_w, sdram_cas_n_w, sdram_we_n_w;
    wire [1:0]  sdram_ba_w, sdram_dqm_w;
    wire [12:0] sdram_a_w;
    wire [15:0] sdram_dq_w;

    CPU #(
        .INIT_FILE_BASE(INIT_FILE_BASE),
        .MAIN_MEM_DEPTH(MAIN_MEM_DEPTH),
        .L2_CACHE_SIZE(L2_CACHE_SIZE)
    ) cpu (
        .clk(clk_20mhz),
        .reset(cpu_reset),
        .debug_pc(debug_pc),
        .debug_opcode(debug_opcode),
        .debug_state(),
        .retire(retire),
        .irq_src_lines(8'b0),
        .mfi_valid(),     .mfi_pc_rdata(retiring_pc), .mfi_pc_wdata(),  .mfi_insn(),
        .mfi_rs1_addr(),  .mfi_rs2_addr(),  .mfi_rs1_rdata(), .mfi_rs2_rdata(),
        .mfi_rd_addr(),   .mfi_rd_wdata(),  .mfi_mem_addr(),
        .mfi_mem_rmask(), .mfi_mem_wmask(), .mfi_mem_wdata(), .mfi_mem_rdata(),
        .debug_csr_addr(), .debug_csr_rdata(), .debug_csr_wdata(), .debug_csr_write(),
        .sdram_aclk(clk_20mhz), .sdram_aresetn(!cpu_reset),
        .sdram_clk(sdram_clk_w),   .sdram_cke(sdram_cke_w),
        .sdram_cs_n(sdram_cs_n_w), .sdram_ras_n(sdram_ras_n_w),
        .sdram_cas_n(sdram_cas_n_w), .sdram_we_n(sdram_we_n_w),
        .sdram_ba(sdram_ba_w),     .sdram_a(sdram_a_w),
        .sdram_dq(sdram_dq_w),     .sdram_dqm(sdram_dqm_w)
    );

    // -----------------------------------------------------------------------
    // LED display: retiring PC[9:2] sampled at ~5 Hz on lower 8 LEDs.
    // Upper 8 LEDs dark (available for future demos).
    // -----------------------------------------------------------------------
    reg [21:0] div;
    reg [7:0]  led_r;

    always @(posedge clk_20mhz) begin
        div <= div + 1;
        if (cpu_reset)
            led_r <= 8'b0;
        else if (div == 0 && retire)
            led_r <= retiring_pc[9:2];
    end

    assign led = {8'b0, led_r};

endmodule
