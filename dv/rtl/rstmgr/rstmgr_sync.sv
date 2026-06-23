/***********************************************************
 * rstmgr_sync - Asynchronous assert, synchronous deassert reset synchronizer
 *
 *   rst_n (async low) -> [FF1] -> [FF2] -> sync_rst_n
 *   async path: !rst_n immediately drives both FFs to 0
 *   sync path:  on rst_n release, 1's shift in over 2 clk edges
 ************************************************************/
`ifndef RSTMGR_SYNC__SV
`define RSTMGR_SYNC__SV

module rstmgr_sync (
    input  logic clk,
    input  logic rst_n,
    output logic sync_rst_n
);

    logic ff1, ff2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ff1 <= 1'b0;
            ff2 <= 1'b0;
        end else begin
            ff1 <= 1'b1;
            ff2 <= ff1;
        end
    end

    assign sync_rst_n = ff2;

endmodule
`endif
