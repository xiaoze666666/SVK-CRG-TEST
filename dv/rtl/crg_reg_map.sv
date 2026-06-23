/***********************************************************
 * G100 CRG - Register map (shared across clkmgr/rstmgr/pwrmgr)
 *
 * Each IP occupies a 4KB APB base. All IPs share one APB bus; address
 * decoding inside crg_top routes to the right IP.
 *
 *   clkmgr_base  = 0x00000
 *   rstmgr_base  = 0x01000
 *   pwrmgr_base  = 0x02000
 *
 * Per-IP register offsets are documented inline.
 ************************************************************/
`ifndef CRG_REG_MAP__SV
`define CRG_REG_MAP__SV

package crg_reg_map_pkg;

    // IP base addresses
    localparam logic [31:0] CLKMGR_BASE = 32'h0000_0000;
    localparam logic [31:0] RSTMGR_BASE = 32'h0000_1000;
    localparam logic [31:0] PWRMGR_BASE = 32'h0000_2000;

    // ---- clkmgr registers ----
    localparam logic [31:0] CLKMGR_CLK_CTRL      = CLKMGR_BASE + 32'h00;
    localparam logic [31:0] CLKMGR_PLL_CFG       = CLKMGR_BASE + 32'h04;
    localparam logic [31:0] CLKMGR_PLL_STATUS    = CLKMGR_BASE + 32'h08;
    localparam logic [31:0] CLKMGR_DIV_CFG       = CLKMGR_BASE + 32'h0C;
    localparam logic [31:0] CLKMGR_GATE_CFG      = CLKMGR_BASE + 32'h10;
    localparam logic [31:0] CLKMGR_MUX_CFG       = CLKMGR_BASE + 32'h14;

    // ---- rstmgr registers ----
    localparam logic [31:0] RSTMGR_RST_CTRL      = RSTMGR_BASE + 32'h00;
    localparam logic [31:0] RSTMGR_RST_GLITCH_TH = RSTMGR_BASE + 32'h04;
    localparam logic [31:0] RSTMGR_RST_REASON    = RSTMGR_BASE + 32'h08;
    localparam logic [31:0] RSTMGR_RST_REQ       = RSTMGR_BASE + 32'h0C;

    // ---- pwrmgr registers ----
    localparam logic [31:0] PWRMGR_CTRL          = PWRMGR_BASE + 32'h00;
    localparam logic [31:0] PWRMGR_WAKE_CFG      = PWRMGR_BASE + 32'h04;
    localparam logic [31:0] PWRMGR_WAKE_STATUS   = PWRMGR_BASE + 32'h08;
    localparam logic [31:0] PWRMGR_ISO_CFG       = PWRMGR_BASE + 32'h0C;

    // ---- Reset values (spec) ----
    // clkmgr
    localparam logic [31:0] CLK_CTRL_RST      = 32'h0000_0001; // bypass=1, src=osc
    localparam logic [31:0] PLL_CFG_RST       = 32'h0000_1C81; // refdiv=1, fbdiv=0x72, int mode
    localparam logic [31:0] PLL_STATUS_RST    = 32'h0000_0000;
    localparam logic [31:0] DIV_CFG_RST       = 32'h0000_0000;
    localparam logic [31:0] GATE_CFG_RST      = 32'h0000_0007; // all gates on
    localparam logic [31:0] MUX_CFG_RST       = 32'h0000_0000;
    // rstmgr
    localparam logic [31:0] RST_CTRL_RST      = 32'h0000_0007; // all out of reset
    localparam logic [31:0] RST_GLITCH_TH_RST = 32'h0000_0004;
    localparam logic [31:0] RST_REASON_RST    = 32'h0000_0000;
    localparam logic [31:0] RST_REQ_RST       = 32'h0000_0000;
    // pwrmgr
    localparam logic [31:0] PWR_CTRL_RST      = 32'h0000_0000;
    localparam logic [31:0] WAKE_CFG_RST      = 32'h0000_0000;
    localparam logic [31:0] WAKE_STATUS_RST   = 32'h0000_0000;
    localparam logic [31:0] ISO_CFG_RST       = 32'h0000_0000;

endpackage : crg_reg_map_pkg
`endif
