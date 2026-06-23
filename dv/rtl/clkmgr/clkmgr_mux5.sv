/***********************************************************
 * clkmgr_mux5 - 5:1 glitch-free clock multiplexer
 *
 * Selects among 5 candidate clocks. Uses the same negedge-latched enable
 * principle as clkmgr_mux (2:1), generalized via a one-hot enable bus.
 *
 *   inputs: clk[4:0]
 *   sel[2:0]: 0..4 selects clk[sel]
 *
 * Each clock gets its own synchronized enable, latched on its own negedge.
 * Only the selected clock's enable is allowed high; the others are forced
 * low via a one-hot constraint in the sync chain.
 *
 * BUG_001 (planted): clk[1]'s enable uses posedge instead of negedge.
 ************************************************************/
`ifndef CLKMGR_MUX5__SV
`define CLKMGR_MUX5__SV

module clkmgr_mux5 (
    input  logic [4:0] clk,        // 5 candidate clocks
    input  logic [2:0] sel,        // 0..4
    output logic       clk_out
);

    // One-hot decode of sel, synced into each clock domain
    genvar i;
    generate
        for (i = 0; i < 5; i++) begin : g_en
            logic [1:0] sync_q;
            logic       target;     // 1 if this clock is selected
            assign target = (sel == i[2:0]);

            // sync target into clk[i] domain
            always_ff @(posedge clk[i] or negedge target) begin
                if (!target) sync_q <= 2'b00;
                else         sync_q <= {sync_q[0], 1'b1};
            end
        end
    endgenerate

    // Per-clock enable latched on negedge (so it changes only when clock is low)
    logic [4:0] en;
    always_ff @(negedge clk[0]) en[0] <= g_en[0].sync_q[1];
    // BUG_001: clk[1]'s enable latched on posedge instead of negedge
    always_ff @(posedge clk[1]) en[1] <= g_en[1].sync_q[1];
    always_ff @(negedge clk[2]) en[2] <= g_en[2].sync_q[1];
    always_ff @(negedge clk[3]) en[3] <= g_en[3].sync_q[1];
    always_ff @(negedge clk[4]) en[4] <= g_en[4].sync_q[1];

    // Final OR of all gated clocks (only one en high at a time due to one-hot)
    assign clk_out = |(clk & en);

endmodule
`endif
