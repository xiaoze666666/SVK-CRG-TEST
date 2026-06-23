/***********************************************************
 * clkmgr_mux - Glitch-free clock multiplexer (clkmgr internal)
 *
 * Two-stage enable-gated mux. sel is synchronized into both clka and clkb
 * domains; enable latched on falling edge of each clock so it only changes
 * when that clock is low -> no runt pulse.
 *
 * BUG_001 (planted): enb_q is latched on posedge clkb instead of negedge.
 * When switching A->B while clkb is high, enb_q asserts and gates in a
 * partial high pulse -> output runt. Caught by clkmgr_mux_vseq + SVA.
 ************************************************************/
`ifndef CLKMGR_MUX__SV
`define CLKMGR_MUX__SV

module clkmgr_mux (
    input  logic clka,
    input  logic clkb,
    input  logic sel,      // 0 = A, 1 = B
    output logic clk_out
);

    logic [1:0] sel_a_sync_q;
    logic [1:0] sel_b_sync_q;

    always_ff @(posedge clka or negedge sel) begin
        if (!sel) sel_a_sync_q <= 2'b00;
        else      sel_a_sync_q <= {sel_a_sync_q[0], 1'b1};
    end
    always_ff @(posedge clkb or negedge sel) begin
        if (sel) sel_b_sync_q <= 2'b00;
        else     sel_b_sync_q <= {sel_b_sync_q[0], 1'b1};
    end

    logic sel_a, sel_b;
    assign sel_a = sel_a_sync_q[1];
    assign sel_b = sel_b_sync_q[1];

    logic ena_q, enb_q;
    always_ff @(negedge clka) ena_q <= sel_a;
    // BUG_001: posedge clkb instead of negedge clkb
    always_ff @(posedge clkb) enb_q <= sel_b;

    assign clk_out = (clka & ena_q) | (clkb & enb_q);

endmodule
`endif
