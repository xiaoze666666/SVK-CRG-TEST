/***********************************************************
 * rstmgr_top - Reset manager IP top
 *
 * Combines POR/WDG/DBG/SW reset sources, glitch-filters POR, syncs to
 * each domain clock, exposes reset reason register.
 *
 * BUG_005 (planted): RST_GLITCH_TH readback returns glitch_th + 1.
 * Caught by rstmgr_common_vseq (csr_hw_reset).
 ************************************************************/
`ifndef RSTMGR_TOP__SV
`define RSTMGR_TOP__SV

`include "../crg_reg_map.sv"
`include "rstmgr_sync.sv"
`include "rstmgr_filter.sv"

module rstmgr_top (
    input  logic        apb_clk,
    input  logic        apb_rst_n,

    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,

    // External async resets
    input  logic        por_rst_n,
    input  logic        wdg_rst_n,
    input  logic        dbg_rst_n,
    input  logic        sw_rst_n,

    // Domain clocks (from clkmgr)
    input  logic        cpu_clk,
    input  logic        gpu_clk,
    input  logic        ddr_clk,

    // Domain reset enables (from reg)
    // (output domain resets below)

    // Per-domain reset outputs
    output logic        cpu_rst_n,
    output logic        gpu_rst_n,
    output logic        ddr_rst_n,

    // Reset reason to pwrmgr / SoC
    output logic [31:0] rst_reason_o
);

    import crg_reg_map_pkg::*;

    // ---- Registers ----
    logic [31:0] rst_ctrl_q,      rst_ctrl_next;
    logic [31:0] rst_glitch_th_q, rst_glitch_th_next;
    logic [31:0] rst_reason_q;
    logic [31:0] rst_req_q,       rst_req_next;

    logic wr_access, rd_access;
    logic [31:0] addr_off;
    assign addr_off  = {paddr[11:2], 2'b00};
    assign wr_access = psel & penable & pwrite;
    assign rd_access = psel & penable & ~pwrite;
    assign pready    = 1'b1;
    assign pslverr   = 1'b0;

    always_comb begin
        rst_ctrl_next      = rst_ctrl_q;
        rst_glitch_th_next = rst_glitch_th_q;
        rst_req_next       = rst_req_q;
        if (wr_access) begin
            case (addr_off)
                32'h00: rst_ctrl_next      = pwdata;
                32'h04: rst_glitch_th_next = pwdata;
                32'h0C: rst_req_next       = pwdata;
                default: ;
            endcase
        end
    end

    always_ff @(posedge apb_clk or negedge apb_rst_n) begin
        if (!apb_rst_n) begin
            rst_ctrl_q      <= RST_CTRL_RST;
            rst_glitch_th_q <= RST_GLITCH_TH_RST;
            rst_req_q       <= RST_REQ_RST;
        end else begin
            rst_ctrl_q      <= rst_ctrl_next;
            rst_glitch_th_q <= rst_glitch_th_next;
            rst_req_q       <= rst_req_next;
        end
    end

    // Reset reason: latched on any reset source assertion
    always_ff @(posedge apb_clk or negedge apb_rst_n) begin
        if (!apb_rst_n)
            rst_reason_q <= RST_REASON_RST;
        else begin
            if (!por_rst_n)        rst_reason_q[0] <= 1'b1;
            else if (!wdg_rst_n)   rst_reason_q[1] <= 1'b1;
            else if (!dbg_rst_n)   rst_reason_q[2] <= 1'b1;
            else if (!sw_rst_n)    rst_reason_q[3] <= 1'b1;
            else if (rst_req_q[0]) rst_reason_q[4] <= 1'b1;
        end
    end
    assign rst_reason_o = rst_reason_q;

    // BUG_005: readback of glitch_th returns th+1
    logic [7:0] glitch_th_readback;
    assign glitch_th_readback = rst_glitch_th_q[7:0] + 8'd1;

    always_comb begin
        prdata = 32'h0;
        if (rd_access) begin
            case (addr_off)
                32'h00: prdata = rst_ctrl_q;
                32'h04: prdata = {24'b0, glitch_th_readback}; // BUG_005
                32'h08: prdata = rst_reason_q;
                32'h0C: prdata = rst_req_q;
                default: prdata = 32'h0;
            endcase
        end
    end

    // ---- Field decode ----
    logic rst_cpu_en = rst_ctrl_q[0];
    logic rst_gpu_en = rst_ctrl_q[1];
    logic rst_ddr_en = rst_ctrl_q[2];

    // ---- Tree: AND of async sources ----
    logic tree_rst_n;
    assign tree_rst_n = por_rst_n & wdg_rst_n & dbg_rst_n & sw_rst_n;

    // ---- Per-domain sync (gated by domain enable) ----
    logic cpu_sync_n, gpu_sync_n, ddr_sync_n;
    rstmgr_sync u_sync_cpu (.clk(cpu_clk), .rst_n(tree_rst_n & rst_cpu_en), .sync_rst_n(cpu_sync_n));
    rstmgr_sync u_sync_gpu (.clk(gpu_clk), .rst_n(tree_rst_n & rst_gpu_en), .sync_rst_n(gpu_sync_n));
    rstmgr_sync u_sync_ddr (.clk(ddr_clk), .rst_n(tree_rst_n & rst_ddr_en), .sync_rst_n(ddr_sync_n));

    assign cpu_rst_n = cpu_sync_n;
    assign gpu_rst_n = gpu_sync_n;
    assign ddr_rst_n = ddr_sync_n;

    // ---- Glitch filter on POR (sample, not used internally for tree) ----
    logic por_filtered_n;
    rstmgr_filter u_gf (
        .clk(apb_clk), .in_rst_n(por_rst_n),
        .glitch_th(rst_glitch_th_q[7:0]), .bypass(1'b0),
        .out_rst_n(por_filtered_n)
    );

endmodule
`endif
