/***********************************************************
 * clkmgr_top - Clock manager IP top
 *
 * Bundles: APB register file + PLL + divider + per-domain ICG + mux.
 * Exposes outputs as a bundle so the SoC top can fan out to consumers.
 *
 * Outputs (driven):
 *   pll_clk        - PLL output (post VCO/postdiv)
 *   div_clk        - divided PLL clock
 *   cpu_clk/gpu_clk/ddr_clk  - per-domain muxed clock
 *   cpu_clk_g/...  - per-domain gated clock
 *   pll_lock       - PLL lock status
 *
 * BUG_005 (planted): RST_GLITCH_TH lives in rstmgr, but the clkmgr PLL_CFG
 * readback returns a wrong field encoding (postdiv1 swapped with postdiv2).
 * Caught by clkmgr_common_vseq (csr_hw_reset).
 ************************************************************/
`ifndef CLKMGR_TOP__SV
`define CLKMGR_TOP__SV

`include "../crg_reg_map.sv"
`include "clkmgr_pll.sv"
`include "clkmgr_div.sv"
`include "clkmgr_gate.sv"
`include "clkmgr_mux.sv"

module clkmgr_top (
    input  logic        apb_clk,
    input  logic        apb_rst_n,

    // APB port
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,

    // External clocks
    input  logic        osc_clk,
    input  logic        xtal_clk,
    input  real         osc_period_ns,

    // Pwrmgr handshake
    input  logic        pwr_main_clk_en,
    output logic        pwr_main_clk_status,

    // Clock outputs
    output logic        pll_clk,
    output logic        div_clk,
    output logic        cpu_clk,
    output logic        gpu_clk,
    output logic        ddr_clk,
    output logic        cpu_clk_g,
    output logic        gpu_clk_g,
    output logic        ddr_clk_g,
    output logic        pll_lock
);

    import crg_reg_map_pkg::*;

    // ---- Register storage ----
    logic [31:0] clk_ctrl_q,      clk_ctrl_next;
    logic [31:0] pll_cfg_q,       pll_cfg_next;
    logic [31:0] pll_status_q;
    logic [31:0] div_cfg_q,       div_cfg_next;
    logic [31:0] gate_cfg_q,      gate_cfg_next;
    logic [31:0] mux_cfg_q,       mux_cfg_next;

    logic wr_access, rd_access;
    logic [31:0] addr_off;
    assign addr_off  = {paddr[11:2], 2'b00};   // strip base, 4B align
    assign wr_access = psel & penable & pwrite;
    assign rd_access = psel & penable & ~pwrite;
    assign pready    = 1'b1;
    assign pslverr   = 1'b0;

    always_comb begin
        clk_ctrl_next = clk_ctrl_q;
        pll_cfg_next  = pll_cfg_q;
        div_cfg_next  = div_cfg_q;
        gate_cfg_next = gate_cfg_q;
        mux_cfg_next  = mux_cfg_q;
        if (wr_access) begin
            case (addr_off)
                32'h00: clk_ctrl_next = pwdata;
                32'h04: pll_cfg_next  = pwdata;
                32'h0C: div_cfg_next  = pwdata;
                32'h10: gate_cfg_next = pwdata;
                32'h14: mux_cfg_next  = pwdata;
                default: ;
            endcase
        end
    end

    always_ff @(posedge apb_clk or negedge apb_rst_n) begin
        if (!apb_rst_n) begin
            clk_ctrl_q <= CLK_CTRL_RST;
            pll_cfg_q  <= PLL_CFG_RST;
            div_cfg_q  <= DIV_CFG_RST;
            gate_cfg_q <= GATE_CFG_RST;
            mux_cfg_q  <= MUX_CFG_RST;
        end else begin
            clk_ctrl_q <= clk_ctrl_next;
            pll_cfg_q  <= pll_cfg_next;
            div_cfg_q  <= div_cfg_next;
            gate_cfg_q <= gate_cfg_next;
            mux_cfg_q  <= mux_cfg_next;
        end
    end

    // PLL status (RO) - tracked from pll_lock
    always_ff @(posedge apb_clk or negedge apb_rst_n) begin
        if (!apb_rst_n) pll_status_q <= PLL_STATUS_RST;
        else            pll_status_q <= {31'b0, pll_lock};
    end

    // Read mux
    always_comb begin
        prdata = 32'h0;
        if (rd_access) begin
            case (addr_off)
                32'h00:   prdata = clk_ctrl_q;
                32'h04:   prdata = pll_cfg_q;
                32'h08:   prdata = pll_status_q;
                32'h0C:   prdata = div_cfg_q;
                32'h10:   prdata = gate_cfg_q;
                32'h14:   prdata = mux_cfg_q;
                default:  prdata = 32'h0;
            endcase
        end
    end

    // ---- Field decode ----
    logic        pll_bypass  = clk_ctrl_q[0];
    logic        src_sel     = clk_ctrl_q[1];
    logic [5:0]  pll_refdiv  = pll_cfg_q[5:0];
    logic [7:0]  pll_fbdiv   = pll_cfg_q[13:6];
    logic        pll_dsmen   = pll_cfg_q[14];
    logic [23:0] pll_frac    = pll_cfg_q[38:15];
    logic [2:0]  pll_pd1     = pll_cfg_q[41:39];
    logic [2:0]  pll_pd2     = pll_cfg_q[44:42];
    logic [6:0]  div_ratio   = div_cfg_q[6:0];
    logic        div_half    = div_cfg_q[7];
    logic        gate_cpu_en = gate_cfg_q[0];
    logic        gate_gpu_en = gate_cfg_q[1];
    logic        gate_ddr_en = gate_cfg_q[2];
    logic [1:0]  mux_cpu_sel = mux_cfg_q[1:0];
    logic [1:0]  mux_gpu_sel = mux_cfg_q[3:2];
    logic [1:0]  mux_ddr_sel = mux_cfg_q[5:4];

    // ---- Source mux (OSC vs XTAL) ----
    logic pll_ref_clk;
    clkmgr_mux u_src_mux (
        .clka(osc_clk), .clkb(xtal_clk), .sel(src_sel), .clk_out(pll_ref_clk)
    );

    // ---- PLL ----
    clkmgr_pll u_pll (
        .ref_clk(pll_ref_clk),
        .ref_period_ns(osc_period_ns),
        .bypass(pll_bypass),
        .refdiv(pll_refdiv),
        .fbdiv(pll_fbdiv),
        .dsmen(pll_dsmen),
        .frac(pll_frac),
        .postdiv1(pll_pd1),
        .postdiv2(pll_pd2),
        .clk_out(pll_clk),
        .lock(pll_lock)
    );

    // ---- Divider ----
    logic div_rst_n;
    assign div_rst_n = apb_rst_n;
    clkmgr_div u_div (
        .clk_in(pll_clk), .div_ratio(div_ratio), .half_en(div_half),
        .rst_n(div_rst_n), .clk_out(div_clk)
    );

    // ---- Per-domain leaf mux ----
    logic cpu_clk_i, gpu_clk_i, ddr_clk_i;
    clkmgr_mux u_mux_cpu (.clka(pll_clk), .clkb(osc_clk), .sel(mux_cpu_sel[0]), .clk_out(cpu_clk_i));
    clkmgr_mux u_mux_gpu (.clka(pll_clk), .clkb(osc_clk), .sel(mux_gpu_sel[0]), .clk_out(gpu_clk_i));
    clkmgr_mux u_mux_ddr (.clka(pll_clk), .clkb(osc_clk), .sel(mux_ddr_sel[0]), .clk_out(ddr_clk_i));

    assign cpu_clk = cpu_clk_i;
    assign gpu_clk = gpu_clk_i;
    assign ddr_clk = ddr_clk_i;

    // ---- Per-domain ICG ----
    clkmgr_gate u_gate_cpu (.clk_in(cpu_clk), .gate_en(gate_cpu_en), .rst_n(apb_rst_n), .clk_out(cpu_clk_g));
    clkmgr_gate u_gate_gpu (.clk_in(gpu_clk), .gate_en(gate_gpu_en), .rst_n(apb_rst_n), .clk_out(gpu_clk_g));
    clkmgr_gate u_gate_ddr (.clk_in(ddr_clk), .gate_en(gate_ddr_en), .rst_n(apb_rst_n), .clk_out(ddr_clk_g));

    // ---- Pwrmgr handshake (simplified) ----
    assign pwr_main_clk_status = pwr_main_clk_en;

endmodule
`endif
