/***********************************************************
 * G100 CRG - Register map (3-PLL clock tree version)
 *
 * Three independent PLLs, three domain muxes, three dividers,
 * 10 leaf clocks. Inspired by real multi-PLL SoC clock trees.
 *
 *   PLL_CPU  : VCO 2400M, CK0=800M (cpu cluster),  CK1=480M (axi fabric)
 *   PLL_SOC  : VCO 2400M, CK0=800M  (high fabric),  CK1=800M
 *   PLL_PERI : VCO 250M,  CK0=250M  (peri/qspi),    CK1=125M  (gmac)
 ************************************************************/
`ifndef CRG_REG_MAP__SV
`define CRG_REG_MAP__SV

package crg_reg_map_pkg;

    localparam logic [31:0] CLKMGR_BASE = 32'h0000_0000;
    localparam logic [31:0] RSTMGR_BASE = 32'h0000_1000;
    localparam logic [31:0] PWRMGR_BASE = 32'h0000_2000;

    // ---- clkmgr registers ----
    localparam logic [31:0] CLKMGR_PLL_CPU_CFG0    = CLKMGR_BASE + 32'h00;
    localparam logic [31:0] CLKMGR_PLL_CPU_CFG1    = CLKMGR_BASE + 32'h04;
    localparam logic [31:0] CLKMGR_PLL_CPU_STATUS  = CLKMGR_BASE + 32'h08;
    localparam logic [31:0] CLKMGR_PLL_SOC_CFG0    = CLKMGR_BASE + 32'h0C;
    localparam logic [31:0] CLKMGR_PLL_SOC_CFG1    = CLKMGR_BASE + 32'h10;
    localparam logic [31:0] CLKMGR_PLL_SOC_STATUS  = CLKMGR_BASE + 32'h14;
    localparam logic [31:0] CLKMGR_PLL_PERI_CFG0   = CLKMGR_BASE + 32'h18;
    localparam logic [31:0] CLKMGR_PLL_PERI_CFG1   = CLKMGR_BASE + 32'h1C;
    localparam logic [31:0] CLKMGR_PLL_PERI_STATUS = CLKMGR_BASE + 32'h20;
    localparam logic [31:0] CLKMGR_MUX_CFG         = CLKMGR_BASE + 32'h24;
    localparam logic [31:0] CLKMGR_DIV_CFG         = CLKMGR_BASE + 32'h28;
    localparam logic [31:0] CLKMGR_GATE_CFG        = CLKMGR_BASE + 32'h2C;

    // ---- rstmgr / pwrmgr registers (unchanged) ----
    localparam logic [31:0] RSTMGR_RST_CTRL      = RSTMGR_BASE + 32'h00;
    localparam logic [31:0] RSTMGR_RST_GLITCH_TH = RSTMGR_BASE + 32'h04;
    localparam logic [31:0] RSTMGR_RST_REASON    = RSTMGR_BASE + 32'h08;
    localparam logic [31:0] RSTMGR_RST_REQ       = RSTMGR_BASE + 32'h0C;
    localparam logic [31:0] PWRMGR_CTRL          = PWRMGR_BASE + 32'h00;
    localparam logic [31:0] PWRMGR_WAKE_CFG      = PWRMGR_BASE + 32'h04;
    localparam logic [31:0] PWRMGR_WAKE_STATUS   = PWRMGR_BASE + 32'h08;
    localparam logic [31:0] PWRMGR_ISO_CFG       = PWRMGR_BASE + 32'h0C;

    // ---- PLL reset values ----
    // cfg0 layout: [bypass:0][refdiv:7:2][fbdiv:15:8]  (upper bits reserved)
    // cfg1 layout: [pd2:31:29][pd1:28:26][frac:25:2][dsmen:0]
    //
    // PLL_CPU: refdiv=1, fbdiv=96 -> Fvco=25*96=2400M; pd1=3 -> CK0=800M, pd2=5 -> CK1=480M
    //   cfg0 = (0x60<<8) | (1<<2) | 0 = 0x6004
    //   cfg1 = (5<<29) | (3<<26) = 0xA0000000 | 0x0C000000 = 0xAC000000
    localparam logic [31:0] PLL_CPU_CFG0_RST    = 32'h0000_6004;
    localparam logic [31:0] PLL_CPU_CFG1_RST    = 32'hAC00_0000;
    localparam logic [31:0] PLL_CPU_STATUS_RST  = 32'h0000_0000;
    // PLL_SOC: refdiv=1, fbdiv=96 -> Fvco=2400M; pd1=3 -> CK0=800M, pd2=0(as /1) -> CK1=2400M
    //   For simplicity both pd=3: CK0=800, CK1=800
    localparam logic [31:0] PLL_SOC_CFG0_RST    = 32'h0000_6004;
    localparam logic [31:0] PLL_SOC_CFG1_RST    = 32'h0C00_0000;  // pd2=0, pd1=3
    localparam logic [31:0] PLL_SOC_STATUS_RST  = 32'h0000_0000;
    // PLL_PERI: refdiv=1, fbdiv=10 -> Fvco=250M; pd1=1 -> CK0=250M, pd2=2 -> CK1=125M
    //   cfg0 = (0x0A<<8) | (1<<2) = 0x0A04
    //   cfg1 = (2<<29) | (1<<26) = 0x40000000 | 0x08000000 = 0x48000000
    localparam logic [31:0] PLL_PERI_CFG0_RST   = 32'h0000_0A04;
    localparam logic [31:0] PLL_PERI_CFG1_RST   = 32'h4800_0000;
    localparam logic [31:0] PLL_PERI_STATUS_RST = 32'h0000_0000;

    localparam logic [31:0] MUX_CFG_RST         = 32'h0000_0000;
    localparam logic [31:0] DIV_CFG_RST         = 32'h0000_0000;
    localparam logic [31:0] GATE_CFG_RST        = 32'h0000_03FF;  // 10 leaves gated ON

    // rstmgr / pwrmgr (unchanged)
    localparam logic [31:0] RST_CTRL_RST      = 32'h0000_0007;
    localparam logic [31:0] RST_GLITCH_TH_RST = 32'h0000_0004;
    localparam logic [31:0] RST_REASON_RST    = 32'h0000_0000;
    localparam logic [31:0] RST_REQ_RST       = 32'h0000_0000;
    localparam logic [31:0] PWR_CTRL_RST      = 32'h0000_0000;
    localparam logic [31:0] WAKE_CFG_RST      = 32'h0000_0000;
    localparam logic [31:0] WAKE_STATUS_RST   = 32'h0000_0000;
    localparam logic [31:0] ISO_CFG_RST       = 32'h0000_0000;

endpackage : crg_reg_map_pkg
`endif
