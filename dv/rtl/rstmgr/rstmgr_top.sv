/***********************************************************
 * rstmgr_top - 8-domain reset tree
 *
 * Structure mirrors the clock tree: each leaf clock domain gets its own
 * reset synchronizer. This is the canonical pattern in real SoCs.
 *
 * Reset sources (async, active-low):
 *   - por_rst_n    : power-on reset
 *   - wdg_rst_n    : watchdog
 *   - dbg_rst_n    : debug reset
 *   - sw_rst_n     : software reset
 *   - low_volt_n   : low-voltage detection (new)
 *   - sec_rst_n    : security violation (new)
 *
 * Tree:
 *   all_sources ANDed -> tree_rst_n (async)
 *   tree_rst_n -> glitch_filter (on apb_clk)
 *   for each domain: sync_rst[domain] = rstmgr_sync(filtered_rst, domain_clk)
 *                                                    gated by per-domain enable
 *
 * Reset reason: latches which source caused the most recent reset.
 *
 * Domains (8, matching clock tree):
 *   0 cpu_core, 1 cpu_aclk, 2 axi_main, 3 ddr_ref,
 *   4 ahb, 5 periph, 6 gmac, 7 qspi
 *
 * BUG_003 (planted): glitch filter counter-clear is inside @(posedge clk).
 *                    If clk stops, filter holds reset forever.
 * BUG_005 (planted): glitch_th readback returns th+1.
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

    // Async reset sources
    input  logic        por_rst_n,
    input  logic        wdg_rst_n,
    input  logic        dbg_rst_n,
    input  logic        sw_rst_n,
    input  logic        low_volt_n,    // low voltage detect
    input  logic        sec_rst_n,     // security violation

    // Domain clocks (8)
    input  logic        cpu_core_clk,
    input  logic        cpu_aclk,
    input  logic        axi_main_clk,
    input  logic        ddr_ref_clk,
    input  logic        ahb_clk,
    input  logic        periph_clk,
    input  logic        gmac_clk,
    input  logic        qspi_clk,

    // Domain reset enables (from reg, 8 bits)
    // (when 0, that domain held in reset regardless of tree)

    // Domain reset outputs (8)
    output logic [7:0]  domain_rst_n,

    output logic [31:0] rst_reason_o
);

    import crg_reg_map_pkg::*;

    // ---- Registers ----
    logic [31:0] rst_ctrl_q,      rst_ctrl_next;       // 8 domain enables
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

    // Reset reason: 6 sources + 2 reserved
    // [0]=por, [1]=wdg, [2]=dbg, [3]=sw, [4]=low_volt, [5]=sec, [6]=sw_req
    always_ff @(posedge apb_clk or negedge apb_rst_n) begin
        if (!apb_rst_n)
            rst_reason_q <= RST_REASON_RST;
        else begin
            if (!por_rst_n)      rst_reason_q[0] <= 1'b1;
            else if (!wdg_rst_n) rst_reason_q[1] <= 1'b1;
            else if (!dbg_rst_n) rst_reason_q[2] <= 1'b1;
            else if (!sw_rst_n)  rst_reason_q[3] <= 1'b1;
            else if (!low_volt_n)rst_reason_q[4] <= 1'b1;
            else if (!sec_rst_n) rst_reason_q[5] <= 1'b1;
            if (rst_req_q[0])    rst_reason_q[6] <= 1'b1;
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
                32'h04: prdata = {24'b0, glitch_th_readback};   // BUG_005
                32'h08: prdata = rst_reason_q;
                32'h0C: prdata = rst_req_q;
                default: prdata = 32'h0;
            endcase
        end
    end

    // ---- Tree: AND of all 6 async sources ----
    logic tree_rst_n;
    assign tree_rst_n = por_rst_n & wdg_rst_n & dbg_rst_n & sw_rst_n &
                        low_volt_n & sec_rst_n;

    // ---- Glitch filter on tree (uses apb_clk as reference) ----
    logic por_filtered_n;
    rstmgr_filter u_gf (
        .clk(apb_clk), .in_rst_n(tree_rst_n),
        .glitch_th(rst_glitch_th_q[7:0]), .bypass(1'b0),
        .out_rst_n(por_filtered_n)
    );

    // ---- Per-domain sync (gated by domain enable from rst_ctrl_q) ----
    // domain_rst_n[i] = sync(por_filtered_n & rst_ctrl_q[i], domain_clk[i])
    logic [7:0] sync_in;
    assign sync_in[0] = por_filtered_n & rst_ctrl_q[0];
    assign sync_in[1] = por_filtered_n & rst_ctrl_q[1];
    assign sync_in[2] = por_filtered_n & rst_ctrl_q[2];
    assign sync_in[3] = por_filtered_n & rst_ctrl_q[3];
    assign sync_in[4] = por_filtered_n & rst_ctrl_q[4];
    assign sync_in[5] = por_filtered_n & rst_ctrl_q[5];
    assign sync_in[6] = por_filtered_n & rst_ctrl_q[6];
    assign sync_in[7] = por_filtered_n & rst_ctrl_q[7];

    logic s0, s1, s2, s3, s4, s5, s6, s7;
    rstmgr_sync u_s0 (.clk(cpu_core_clk), .rst_n(sync_in[0]), .sync_rst_n(s0));
    rstmgr_sync u_s1 (.clk(cpu_aclk),     .rst_n(sync_in[1]), .sync_rst_n(s1));
    rstmgr_sync u_s2 (.clk(axi_main_clk), .rst_n(sync_in[2]), .sync_rst_n(s2));
    rstmgr_sync u_s3 (.clk(ddr_ref_clk),  .rst_n(sync_in[3]), .sync_rst_n(s3));
    rstmgr_sync u_s4 (.clk(ahb_clk),      .rst_n(sync_in[4]), .sync_rst_n(s4));
    rstmgr_sync u_s5 (.clk(periph_clk),   .rst_n(sync_in[5]), .sync_rst_n(s5));
    rstmgr_sync u_s6 (.clk(gmac_clk),     .rst_n(sync_in[6]), .sync_rst_n(s6));
    rstmgr_sync u_s7 (.clk(qspi_clk),     .rst_n(sync_in[7]), .sync_rst_n(s7));

    assign domain_rst_n = {s7, s6, s5, s4, s3, s2, s1, s0};

endmodule
`endif
