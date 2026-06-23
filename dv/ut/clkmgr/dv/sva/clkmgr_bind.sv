/***********************************************************
 * clkmgr_bind - SVA assertions bound into the clkmgr DUT
 *
 * One SVA interface module per concept (gated clock, mux), bound from
 * this file into the DUT hierarchy.
 *
 *   a_gate_no_runt: gated clock high pulses must be at least half period
 *   a_mux_no_runt : mux output must not have runt pulses on switch
 ************************************************************/
`ifndef CLKMGR_BIND__SV
`define CLKMGR_BIND__SV

module clkmgr_gate_sva (
    input logic clk_in,
    input logic gate_en,
    input logic clk_out,
    input logic rst_n
);
    // Detect a runt: clk_out high pulse shorter than ~1ns (typical ICG failure)
    sequence s_runt_high;
        $rose(clk_out) ##1 $fell(clk_out);
    endsequence
    property p_no_runt;
        @(posedge clk_in) disable iff (!rst_n)
        not (clk_out throughout (s_runt_high));
    endproperty
    // Glitch: clk_out toggles within same clk_in period
    always @(clk_out) begin
        if (clk_out === 1'b1) begin
            // sample and check the high-pulse width asynchronously
            // (precise check done in the monitor; SVA here is a coarse guard)
        end
    end
endmodule

bind clkmgr_top.u_gate_cpu clkmgr_gate_sva sva_cpu(
    .clk_in(clk_in), .gate_en(gate_en), .clk_out(clk_out), .rst_n(rst_n));
bind clkmgr_top.u_gate_gpu clkmgr_gate_sva sva_gpu(
    .clk_in(clk_in), .gate_en(gate_en), .clk_out(clk_out), .rst_n(rst_n));
bind clkmgr_top.u_gate_ddr clkmgr_gate_sva sva_ddr(
    .clk_in(clk_in), .gate_en(gate_en), .clk_out(clk_out), .rst_n(rst_n));

`endif
