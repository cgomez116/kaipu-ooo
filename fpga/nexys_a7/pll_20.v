// 25 MHz → 20 MHz PLL for Nexys A7-100T (Artix-7 XC7A100T).
// Replaces the ECP5 EHXPLLL in vendor/kaipu/fpga/basic/pll_20.v.
//
// MMCME2_ADV parameters for 25 MHz → 20 MHz:
//   VCO = CLKIN * CLKFBOUT_MULT_F / DIVCLK_DIVIDE = 25 * 40 / 1 = 1000 MHz
//   (within Artix-7 MMCM range 600–1200 MHz)
//   CLKOUT0 = VCO / CLKOUT0_DIVIDE_F = 1000 / 50 = 20 MHz
//
// locked is asserted when the PLL achieves phase lock.
// clk_20mhz is the clock for all sequential logic; clk_25mhz drives only this PLL.
module pll_20 (
    input  wire clk_25mhz,
    output wire clk_20mhz,
    output wire locked
);
    wire clkfb;

    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKOUT4_CASCADE      ("FALSE"),
        .COMPENSATION         ("ZHOLD"),
        .STARTUP_WAIT         ("FALSE"),
        .DIVCLK_DIVIDE        (1),
        .CLKFBOUT_MULT_F      (40.000),   // VCO = 25 * 40 = 1000 MHz
        .CLKFBOUT_PHASE       (0.000),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),
        .CLKOUT0_DIVIDE_F     (50.000),   // 1000 / 50 = 20 MHz
        .CLKOUT0_PHASE        (0.000),
        .CLKOUT0_DUTY_CYCLE   (0.500),
        .CLKOUT0_USE_FINE_PS  ("FALSE"),
        .CLKIN1_PERIOD        (40.000),   // 1/25 MHz = 40 ns
        .REF_JITTER1          (0.010)
    ) mmcm_inst (
        .CLKFBOUT   (clkfb),
        .CLKFBOUTB  (),
        .CLKOUT0    (clk_20mhz),
        .CLKOUT0B   (),
        .CLKOUT1    (), .CLKOUT1B   (),
        .CLKOUT2    (), .CLKOUT2B   (),
        .CLKOUT3    (), .CLKOUT3B   (),
        .CLKOUT4    (),
        .CLKOUT5    (),
        .CLKOUT6    (),
        .LOCKED     (locked),
        .CLKFBIN    (clkfb),
        .CLKIN1     (clk_25mhz),
        .CLKIN2     (1'b0),
        .CLKINSEL   (1'b1),
        .DADDR      (7'b0),
        .DCLK       (1'b0),
        .DEN        (1'b0),
        .DI         (16'b0),
        .DO         (),
        .DRDY       (),
        .DWE        (1'b0),
        .PSCLK      (1'b0),
        .PSEN       (1'b0),
        .PSINCDEC   (1'b0),
        .PSDONE     (),
        .PWRDWN     (1'b0),
        .RST        (1'b0)
    );
endmodule
