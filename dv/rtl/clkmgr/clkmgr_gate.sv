/***********************************************************
 * clkmgr_gate - Integrated Clock Gating cell (ICG)
 *
 * Standard library ICG. Enable latched on falling edge of clk_in.
 *
 * BUG_004 (planted): latch uses posedge clk_in instead of negedge. When
 * gate_en toggles mid-high, output gets a truncated high pulse.
 * Caught by clkmgr_gate_vseq + SVA in clkmgr_bind.sv.
 ************************************************************/
`ifndef CLKMGR_GATE__SV
`define CLKMGR_GATE__SV

module clkmgr_gate (
    input  logic clk_in,
    input  logic gate_en,
    input  logic rst_n,
    output logic clk_out
);

    logic en_latched;
    // BUG_004: should be 'if (!clk_in)' (falling-edge-latch); using clk_in
    // triggers a runt pulse when gate_en toggles mid-high.
    always_latch begin
        if (!rst_n)      en_latched = 1'b0;
        else if (clk_in) en_latched = gate_en;
    end

    assign clk_out = clk_in & en_latched;

endmodule
`endif
